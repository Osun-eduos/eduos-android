// Everything the screens show, and every action a teacher can take.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'inspection.dart';
import 'models.dart';
import 'parent.dart';
import 'push.dart';
import 'net/api.dart';
import 'rules.dart';
import 'store/local_store.dart';
import 'store/vault.dart';
import 'sync/inspection_sync.dart';
import 'sync/parent_sync.dart';
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
  AppState({required this.vault, required this.api, required this.openStore, required this.defaultServers, this.clock, this.onSignedIn, this.onSignedOut, this.photosDir, PushRegistrar? push}) : push = push ?? NoPush();

  final Vault vault;
  final Api api;
  final Future<LocalStore> Function(String key) openStore;
  final Servers defaultServers;
  final DateTime Function()? clock;
  /// Starts background sync (set by main; left out in tests).
  final Future<void> Function(Servers servers)? onSignedIn;
  final Future<void> Function()? onSignedOut;
  /// Folder for inspection photos waiting to be sent (set by main; tests use a temporary folder).
  final Future<Directory> Function()? photosDir;
  /// Push notifications for parents (Firebase when the app is built with its settings).
  final PushRegistrar push;
  String? _pushToken;
  final List<StreamSubscription<Object?>> _pushSubs = [];
  final _uuid = const Uuid();

  Phase phase = Phase.loading;
  LocalStore? _store;
  SyncEngine? _engine;
  InspectionSync? _inspections;
  ParentSync? _parents;
  ParentData? parentData;
  Snapshot? snapshot;
  /// TEACHER, INSPECTOR or LGA_OFFICER. Phones set up before inspections existed are teachers.
  String role = 'TEACHER';
  String? lga;
  InspectorData? inspector;
  List<LocalInspection> localInspections = [];
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
  bool get isInspector => inspectorRoles.contains(role);
  bool get isParent => role == 'PARENT';
  bool get _hasWorkSet => isInspector ? inspector != null : isParent ? parentData != null : snapshot != null;

  void _engines() {
    _inspections = InspectionSync(api: api, store: store, userName: userName ?? '', lga: lga);
    _parents = ParentSync(api: api, store: store, userName: userName ?? '');
  }

  Future<SyncReport> _runSync() => isInspector ? _inspections!.run() : isParent ? _parents!.run() : _engine!.run();

  Future<void> init() async {
    final apiUrl = await vault.read('apiUrl'), syncUrl = await vault.read('syncUrl');
    api.servers = Servers(api: apiUrl ?? defaultServers.api, sync: syncUrl ?? defaultServers.sync);
    _store = await openStore(await databaseKey(vault));
    _engine = SyncEngine(api: api, store: store, deviceId: await deviceId(vault));
    role = await vault.read('role') ?? 'TEACHER';
    lga = await vault.read('lga');
    await reload();
    _engines();
    if (await vault.read('refreshToken') != null && _hasWorkSet) {
      phase = Phase.ready;
      notifyListeners();
      _startTimer();
      _background();
      unawaited(_registerPush());
      unawaited(sync());
    } else {
      phase = Phase.signedOut;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    final json = await store.snapshotJson();
    snapshot = json == null ? null : Snapshot.fromJson(json);
    final insp = await store.meta('inspector');
    inspector = insp == null ? null : InspectorData.fromJson(jsonDecode(insp) as Map<String, dynamic>);
    final par = await store.meta('parent');
    parentData = par == null ? null : ParentData.fromJson(jsonDecode(par) as Map<String, dynamic>, readHere: await ParentSync.pendingReads(store));
    userName = snapshot?.userName ?? (inspector?.userName.isNotEmpty == true ? inspector!.userName : null) ?? (parentData?.userName.isNotEmpty == true ? parentData!.userName : null) ?? userName;
    drafts = {for (final d in await store.drafts()) d.key: d};
    waitingKeys = await store.pendingDraftKeys();
    localInspections = await store.inspections();
    pending = await store.pendingCount() + await store.inspectionsWaiting();
    notices = await store.notices();
    lastSync = await store.lastSyncAt();
    notifyListeners();
  }

  /// Background sync is best effort: if the platform refuses, the app still syncs whenever it is open.
  void _background() {
    final f = onSignedIn;
    if (f != null) unawaited(f(api.servers).catchError((Object e) => debugPrint('Background sync not scheduled: $e')));
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

  /// Set after a correct password when the account uses two-step sign-in; the sign-in screen then asks for a code.
  String? codeChallenge;

  /// Signs in. Returns an error message, or null when it worked (or when a code is now needed: see [codeChallenge]).
  Future<String?> signIn(String identifier, String password) async {
    try {
      return await _afterSignIn(await api.login(identifier, password));
    } on CodeNeeded catch (c) {
      codeChallenge = c.mfaToken;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Second step of two-step sign-in. Returns an error message, or null when it worked.
  Future<String?> signInWithCode(String code) async {
    final token = codeChallenge;
    if (token == null) return 'Enter your email or phone number and your password again.';
    try {
      final u = await api.loginWithCode(token, code);
      codeChallenge = null;
      return await _afterSignIn(u);
    } on ApiException catch (e) {
      // The step between password and code has expired or run out of tries: start again from the password.
      if (e.status == 401 && e.message.toLowerCase().contains('expired')) {
        codeChallenge = null;
        notifyListeners();
      }
      return e.message;
    }
  }

  void cancelCode() {
    codeChallenge = null;
    notifyListeners();
  }

  Future<String?> _afterSignIn(SignedIn u) async {
    try {
      if (u.role != 'TEACHER' && u.role != 'PARENT' && !inspectorRoles.contains(u.role)) {
        await api.logout();
        return 'This app is for parents, teachers, inspectors and LGA education officers. Use the EduOS website for other accounts.';
      }
      // Someone else used this phone before: start clean so their data is never mixed with this person's.
      if (role != u.role || (snapshot == null && inspector == null && parentData == null)) await store.wipe();
      role = u.role;
      lga = u.lga;
      await vault.write('role', role);
      if (lga != null) {
        await vault.write('lga', lga!);
      } else {
        await vault.delete('lga');
      }
      userName = u.fullName;
      _engines();
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
    final r = await _runSync();
    await reload();
    if (r.outcome != SyncOutcome.synced || !_hasWorkSet) {
      return r.message ?? (isInspector ? 'Could not download your schools. Check your connection and try again.' : 'Could not download your classes. Check your connection and try again.');
    }
    phase = Phase.ready;
    _startTimer();
    _background();
    unawaited(_registerPush());
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    _timer?.cancel();
    for (final s in _pushSubs) {
      unawaited(s.cancel());
    }
    _pushSubs.clear();
    if (_pushToken != null) {
      // Stop pushes to this phone for the person signing out. Best effort: it may be offline.
      try {
        await api.apiDelete('/devices/${Uri.encodeComponent(_pushToken!)}');
      } catch (_) {}
      _pushToken = null;
    }
    if (onSignedOut != null) await onSignedOut!().catchError((Object _) {});
    await api.logout();
    await store.wipe();
    await vault.delete('role');
    await vault.delete('lga');
    if (photosDir != null) {
      try {
        final d = await photosDir!();
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
    snapshot = null;
    inspector = null;
    parentData = null;
    role = 'TEACHER';
    await reload();
    phase = Phase.signedOut;
    notifyListeners();
  }

  // ---- Sync ----

  Future<void> sync() async {
    if (phase != Phase.ready || _engine == null) return;
    syncing = true;
    notifyListeners();
    final r = await _runSync();
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
    return registerDates(today: today, session: s!.session!, editDays: s.teacherEditDays, holidays: s.holidays);
  }

  /// Today's holiday, if today is one.
  Holiday? get holidayToday => snapshot == null ? null : holidayOn(snapshot!.holidays, today);

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

  // ---- Inspections (inspectors and LGA officers) ----

  LocalInspection? localInspection(String clientId) => localInspections.where((i) => i.clientId == clientId).firstOrNull;

  /// Starts a new inspection of [school] dated today, saved on the phone as a draft.
  Future<String> startInspection(SchoolRef school) async {
    final i = LocalInspection(clientId: 'insp-${_uuid.v4()}', schoolId: school.id, schoolName: school.name, visitedOn: today, answers: {});
    await store.saveInspection(i);
    await reload();
    return i.clientId;
  }

  /// Saves changes to a draft. Called as the inspector answers, so nothing is lost if the phone dies.
  Future<void> saveInspection(LocalInspection i) async {
    if (i.status != 'draft') return;
    // Never turn a submitted inspection back into a draft (a screen closing late may still hold the old copy).
    final stored = await store.inspection(i.clientId);
    if (stored == null || stored.status != 'draft') return;
    i.updatedAt = DateTime.now();
    await store.saveInspection(i);
    await reload();
  }

  Future<void> deleteInspection(String clientId) async {
    for (final p in await store.photos(inspectionId: clientId)) {
      try {
        await File(p.path).delete();
      } catch (_) {}
    }
    await store.deleteInspection(clientId);
    await reload();
  }

  /// Submits a finished inspection: it is queued and sent as soon as there is a connection.
  Future<void> submitInspection(String clientId) async {
    final i = await store.inspection(clientId);
    if (i == null || i.status != 'draft') return;
    i
      ..status = 'queued'
      ..updatedAt = DateTime.now();
    await store.saveInspection(i);
    await reload();
    unawaited(sync());
  }

  Future<List<LocalPhoto>> photosFor(String inspectionClientId) => store.photos(inspectionId: inspectionClientId);

  /// Keeps a copy of a photo just taken (the camera's own copy may be cleared by the system) and queues it.
  Future<void> addPhoto(String inspectionClientId, String section, String sourcePath, {String? caption}) async {
    final dir = photosDir == null ? Directory.systemTemp : await photosDir!();
    if (!await dir.exists()) await dir.create(recursive: true);
    final id = 'photo-${_uuid.v4()}';
    final ext = sourcePath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final copy = await File(sourcePath).copy('${dir.path}/$id.$ext');
    await store.savePhoto(LocalPhoto(clientId: id, inspectionId: inspectionClientId, section: section, path: copy.path, caption: caption));
    await reload();
    final i = await store.inspection(inspectionClientId);
    if (i != null && i.status != 'draft') unawaited(sync());
  }

  Future<void> removePhoto(LocalPhoto p) async {
    if (p.status == 'sent') return;
    try {
      await File(p.path).delete();
    } catch (_) {}
    await store.deletePhoto(p.clientId);
    await reload();
  }

  // ---- Parents ----

  /// Tells the server where to push this parent's notifications, and refreshes when one arrives.
  Future<void> _registerPush() async {
    if (!isParent || _pushSubs.isNotEmpty) return;
    try {
      final token = await push.token();
      if (token == null) return;
      Future<void> send(String t) async {
        _pushToken = t;
        await api.apiPost('/devices', {'token': t, 'platform': push.platform});
      }
      await send(token);
      _pushSubs.add(push.tokenChanges.listen((t) => send(t).catchError((Object _) {})));
      _pushSubs.add(push.arrivals.listen((_) => sync()));
    } catch (e) {
      debugPrint('Push not registered: $e');
    }
  }

  /// Marks notifications read now on this phone; the server is told on the next sync.
  Future<void> markRead(Iterable<String> ids) async {
    final unread = ids.where((id) => parentData?.inbox.any((n) => n.id == id && !n.read) ?? false).toList();
    if (unread.isEmpty) return;
    await ParentSync.addPendingReads(store, unread);
    await reload();
    unawaited(sync());
  }

  Child? child(String id) => parentData?.children.where((c) => c.id == id).firstOrNull;

  /// A report card for a term not kept on the phone. Needs a connection.
  Future<ReportCard> reportCard(String studentId, String termId) async {
    final cached = child(studentId)?.latestCard;
    if (cached != null && cached.termId == termId) return cached;
    return ReportCard.fromJson(await _parents!.reportCard(studentId, termId));
  }

  // ---------- Staff clock-in (teachers and school administrators) ----------

  /// Today's mark: 'PRESENT', 'LATE', 'ABSENT' or 'LEAVE'; 'OUT' if not yet marked; 'none' without a staff
  /// record; null until checked (or offline).
  String? clockStatus;

  Future<T> _withRefresh<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ApiException catch (e) {
      if (e.status != 401 || !await api.refresh()) rethrow;
      return await fn();
    }
  }

  /// Asks the API whether the signed-in member of staff is marked in today. Quietly does nothing offline.
  Future<void> loadClockStatus() async {
    try {
      final r = await _withRefresh(() => api.apiGet('/staff-attendance/me'));
      clockStatus = r['linked'] != true ? 'none' : (r['today']?['status'] as String? ?? 'OUT');
      notifyListeners();
    } catch (_) {}
  }

  /// Clocks in for today. Returns a message for the person.
  Future<String> clockIn() async {
    try {
      final r = await _withRefresh(() => api.apiPost('/staff-attendance/clock-in', {}));
      clockStatus = r['status'] as String?;
      notifyListeners();
      return clockStatus == 'LATE' ? 'Clocked in, marked late.' : 'Clocked in. Have a good day.';
    } on ApiException catch (e) {
      return e.offline ? 'Clocking in needs a connection. Try again when you have signal.' : e.message;
    }
  }
}
