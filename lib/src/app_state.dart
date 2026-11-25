// Everything the screens show, and every action a teacher can take.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'net/api.dart';
import 'rules.dart';
import 'store/local_store.dart';
import 'store/vault.dart';
import 'sync/sync_engine.dart';

enum Phase { loading, signedOut, changePassword, ready }

class RegisterView {
  RegisterView({required this.marks, required this.onServer, required this.waiting, required this.editable, this.lockedReason});
  final Map<String, Mark> marks;
  final bool onServer; // a register for this day reached the server
  final bool waiting; // saved on this phone, not yet sent
  final bool editable;
  final String? lockedReason;
  bool get taken => onServer || waiting;
}

class SheetView {
  SheetView({required this.status, required this.marks, required this.editable, required this.waiting, this.lockedReason, this.returnNote});
  /// NOT_STARTED, DRAFT, SUBMITTED, APPROVED or RETURNED, as the teacher should see it.
  final String status;
  final Map<String, Marks> marks;
  final bool editable;
  final bool waiting;
  final String? lockedReason;
  final String? returnNote;
}

const statusText = {
  'NOT_STARTED': 'Not started',
  'DRAFT': 'Draft',
  'SUBMITTED': 'Submitted',
  'APPROVED': 'Approved',
  'RETURNED': 'Returned',
};

class AppState extends ChangeNotifier {
  AppState({required this.vault, required this.api, required this.openStore, required this.defaultServers, this.clock});

  final Vault vault;
  final Api api;
  final Future<LocalStore> Function(String key) openStore;
  final Servers defaultServers;
  final DateTime Function()? clock;
  final _uuid = const Uuid();

  Phase phase = Phase.loading;
  LocalStore? _store;
  SyncEngine? _engine;
  Snapshot? snapshot;
  Map<String, Draft> drafts = {};
  Set<String> waitingKeys = {};
  int pending = 0;
  List<Notice> notices = [];
  DateTime? lastSync;
  bool syncing = false;
  String? syncMessage;
  bool offline = false;
  String? userName;
  Timer? _timer;

  LocalStore get store => _store!;
  String get today => todayNG(clock?.call());

  Future<void> init() async {
    final apiUrl = await vault.read('apiUrl'), syncUrl = await vault.read('syncUrl');
    api.servers = Servers(api: apiUrl ?? defaultServers.api, sync: syncUrl ?? defaultServers.sync);
    _store = await openStore(await databaseKey(vault));
    _engine = SyncEngine(api: api, store: store, deviceId: await deviceId(vault));
    await reload();
    if (await vault.read('refreshToken') != null && snapshot != null) {
      phase = Phase.ready;
      notifyListeners();
      _startTimer();
      unawaited(sync());
    } else {
      phase = Phase.signedOut;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    final json = await store.snapshotJson();
    snapshot = json == null ? null : Snapshot.fromJson(json);
    userName = snapshot?.userName ?? userName;
    drafts = {for (final d in await store.drafts()) d.key: d};
    waitingKeys = await store.pendingDraftKeys();
    pending = await store.pendingCount();
    notices = await store.notices();
    lastSync = await store.lastSyncAt();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ---- Sign-in ----

  Future<void> setServers(String apiUrl, String syncUrl) async {
    String clean(String s) => s.trim().replaceAll(RegExp(r'/+$'), '');
    api.servers = Servers(api: clean(apiUrl), sync: clean(syncUrl));
    await vault.write('apiUrl', api.servers.api);
    await vault.write('syncUrl', api.servers.sync);
  }

  /// Signs in. Returns an error message, or null when it worked.
  Future<String?> signIn(String identifier, String password) async {
    try {
      final u = await api.login(identifier, password);
      if (u.role != 'TEACHER') {
        await api.logout();
        return 'This app is for teachers. Use the EduOS website for other accounts.';
      }
      userName = u.fullName;
      if (u.mustChangePassword) {
        phase = Phase.changePassword;
        notifyListeners();
        return null;
      }
      return await _firstSync();
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> changePassword(String current, String next) async {
    try {
      await api.changePassword(current, next);
      return await _firstSync();
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> _firstSync() async {
    final r = await _engine!.run();
    await reload();
    if (r.outcome != SyncOutcome.synced || snapshot == null) {
      return r.message ?? 'Could not download your classes. Check your connection and try again.';
    }
    phase = Phase.ready;
    _startTimer();
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    _timer?.cancel();
    await api.logout();
    await store.wipe();
    snapshot = null;
    await reload();
    phase = Phase.signedOut;
    notifyListeners();
  }

  // ---- Sync ----

  Future<void> sync() async {
    if (phase != Phase.ready || _engine == null) return;
    syncing = true;
    notifyListeners();
    final r = await _engine!.run();
    syncing = false;
    offline = r.outcome == SyncOutcome.offline;
    syncMessage = r.outcome == SyncOutcome.synced ? null : r.message;
    await reload();
    if (r.outcome == SyncOutcome.signedOut) {
      // Keep unsent changes; they go once the teacher signs in again.
      _timer?.cancel();
      phase = Phase.signedOut;
      notifyListeners();
    }
  }

  Future<void> dismissNotice(int id) async {
    await store.dismissNotice(id);
    await reload();
  }

  // ---- Registers ----

  static String registerKey(String classId, String date) => 'reg:$classId:$date';

  List<String> registerDays() {
    final s = snapshot;
    if (s?.session == null) return [];
    return registerDates(today: today, session: s!.session!, editDays: s.teacherEditDays);
  }

  RegisterView registerFor(SchoolClass c, String date) {
    final key = registerKey(c.id, date);
    final d = drafts[key];
    final server = c.registers.where((r) => r.date == date).firstOrNull;
    final marks = <String, Mark>{};
    for (final m in server?.marks ?? <Mark>[]) {
      marks[m.studentId] = m;
    }
    if (d != null) {
      for (final m in (d.data['marks'] as List).map((m) => Mark.fromJson(m))) {
        marks[m.studentId] = m;
      }
    }
    final allowed = registerDays().contains(date);
    return RegisterView(
      marks: marks,
      onServer: server != null,
      waiting: waitingKeys.contains(key),
      editable: allowed,
      lockedReason: allowed ? null : 'Class teachers can change registers for the last ${snapshot?.teacherEditDays ?? 7} days. Ask your school administrator to correct older ones.',
    );
  }

  Future<void> saveRegister(SchoolClass c, String date, List<Mark> marks) async {
    final key = registerKey(c.id, date);
    final label = '${c.name} register for ${DateFormat('EEE d MMM').format(parseDate(date))}';
    final payload = {'classId': c.id, 'date': date, 'marks': marks.map((m) => m.toJson()).toList()};
    await store.record(
      draftKey: key,
      draft: {'marks': payload['marks']},
      event: OutboxEvent(id: _uuid.v4(), type: 'attendance.register', payload: payload, occurredAt: DateTime.now(), draftKey: key, label: label),
    );
    await reload();
    unawaited(sync());
  }

  // ---- Scores ----

  static String scoresKey(String classSubjectId) => 'scores:$classSubjectId';

  SheetView sheetFor(Subject s) {
    final term = snapshot?.term;
    final d = drafts[scoresKey(s.classSubjectId)];
    final marks = <String, Marks>{for (final sc in s.sheet?.scores ?? <Score>[]) sc.studentId: Map.of(sc.marks)};
    final draftMarks = (d?.data['marks'] as Map<String, dynamic>?) ?? {};
    draftMarks.forEach((sid, m) => marks[sid] = {...?marks[sid], ...marksFromJson(m)});
    final submittedHere = d?.data['submitted'] == true;
    var status = submittedHere ? 'SUBMITTED' : (s.sheet?.status ?? 'NOT_STARTED');
    if (status == 'NOT_STARTED' && draftMarks.isNotEmpty) status = 'DRAFT';
    String? locked;
    if (term == null) {
      locked = 'The Ministry has not set the current term yet.';
    } else if (s.released) {
      locked = 'These results have been released.';
    } else if (status == 'SUBMITTED') {
      locked = 'Submitted for approval. Your school administrator can return it if something needs changing.';
    } else if (status == 'APPROVED') {
      locked = 'Approved. Your school administrator can return it if something needs changing.';
    }
    return SheetView(
      status: status,
      marks: marks,
      editable: locked == null,
      waiting: waitingKeys.contains(scoresKey(s.classSubjectId)),
      lockedReason: locked,
      returnNote: status == 'RETURNED' ? s.sheet?.returnNote : null,
    );
  }

  /// Saves changed marks: [changes] maps student id to their full set of marks (null where not entered).
  Future<void> saveScores(Subject s, Map<String, Marks> changes) async {
    if (changes.isEmpty) return;
    final key = scoresKey(s.classSubjectId);
    final d = drafts[key];
    final merged = Map<String, dynamic>.from((d?.data['marks'] as Map<String, dynamic>?) ?? {});
    changes.forEach((sid, m) => merged[sid] = m);
    await store.record(
      draftKey: key,
      draft: {'marks': merged, 'submitted': d?.data['submitted'] == true},
      event: OutboxEvent(
        id: _uuid.v4(),
        type: 'scores.save',
        payload: {
          'classSubjectId': s.classSubjectId,
          'scores': changes.entries.map((e) => {'studentId': e.key, 'marks': e.value}).toList(),
        },
        occurredAt: DateTime.now(),
        draftKey: key,
        label: '${s.name} scores for ${s.className}',
      ),
    );
    await reload();
    unawaited(sync());
  }

  Future<void> submitScores(Subject s) async {
    final key = scoresKey(s.classSubjectId);
    final d = drafts[key];
    await store.record(
      draftKey: key,
      draft: {'marks': (d?.data['marks'] as Map<String, dynamic>?) ?? {}, 'submitted': true},
      event: OutboxEvent(
        id: _uuid.v4(),
        type: 'scores.submit',
        payload: {'classSubjectId': s.classSubjectId},
        occurredAt: DateTime.now(),
        draftKey: key,
        label: 'Submitting ${s.name} scores for ${s.className}',
      ),
    );
    await reload();
    unawaited(sync());
  }
}
