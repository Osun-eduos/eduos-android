// End-to-end check against a running eduos-api and eduos-sync with the walkthrough data.
// Skipped unless EDUOS_LIVE=1. Run: EDUOS_LIVE=1 flutter test test/integration/live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:eduos_mobile/src/app_state.dart';
import 'package:eduos_mobile/src/models.dart';
import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../fixtures.dart';

final live = Platform.environment['EDUOS_LIVE'] == '1';
final apiUrl = Platform.environment['EDUOS_API_URL'] ?? 'http://localhost:3000';
final syncUrl = Platform.environment['EDUOS_SYNC_URL'] ?? 'http://localhost:4000';

Future<Map<String, dynamic>> call(String method, String path, {String? token, Object? body}) async {
  final r = http.Request(method, Uri.parse('$apiUrl$path'))
    ..headers.addAll({'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'});
  if (body != null) r.body = jsonEncode(body);
  final res = await http.Response.fromStream(await r.send());
  final b = res.body.isEmpty ? null : jsonDecode(res.body);
  if (res.statusCode >= 400) throw Exception('$method $path ${res.statusCode} ${res.body}');
  return b is Map<String, dynamic> ? b : {'list': b};
}

void main() {
  test('a teacher signs in, works offline-first, and the school sees the results', () async {
    // The school gives Tunde a maths class in JSS 2B with one student.
    final principal = (await call('POST', '/auth/login', body: {'identifier': 'principal@osogbo.test', 'password': 'Permanent2026'}))['accessToken'] as String;
    final classes = (await call('GET', '/classes', token: principal))['list'] as List;
    final jss2b = classes.firstWhere((c) => c['name'] == 'JSS 2B');
    final teachers = (await call('GET', '/users?role=TEACHER', token: principal))['list'] as List;
    final tunde = teachers.firstWhere((t) => t['fullName'] == 'Tunde Olaniyan');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final enrolled = await call('POST', '/students', token: principal, body: {
      'surname': 'Phone', 'firstName': 'Test$stamp', 'sex': 'M', 'dateOfBirth': '2013-05-05', 'classArmId': jss2b['id'], 'admittedOn': '2026-09-15', 'confirmDuplicate': true,
    });
    final studentId = enrolled['student']['id'] as String;
    final subjects = (await call('GET', '/classes/${jss2b['id']}/subjects', token: principal))['list'] as List;
    if (!subjects.any((s) => s['code'] == 'MTH')) {
      await call('POST', '/classes/${jss2b['id']}/subjects', token: principal, body: {'subjectCode': 'MTH', 'teacherId': tunde['id']});
    }

    // The teacher signs in on the phone.
    final vault = MemoryVault();
    final store = await memoryStore();
    final servers = Servers(api: apiUrl, sync: syncUrl);
    final app = AppState(vault: vault, api: Api(client: http.Client(), vault: vault, servers: servers), openStore: (_) async => store, defaultServers: servers);
    await app.init();
    expect(await app.signIn('tunde@osogbo.test', 'Permanent2026'), isNull);
    expect(app.phase, Phase.ready);
    expect(vault.values['refreshToken'], isNotNull);
    final snap = app.snapshot!;
    final maths = snap.subjects.firstWhere((s) => s.className == 'JSS 2B' && s.code == 'MTH');
    expect(maths.students.map((s) => s.id), contains(studentId));

    // Today's register for JSS 2A.
    final jss2a = snap.classes.firstWhere((c) => c.name == 'JSS 2A');
    final today = app.today;
    if (app.registerDays().contains(today)) {
      final roll = jss2a.students.where((s) => s.admittedOn.compareTo(today) <= 0).toList();
      await app.saveRegister(jss2a, today, [for (final s in roll) Mark(studentId: s.id, status: s == roll.first ? 'LATE' : 'PRESENT', note: s == roll.first ? 'Rain' : null)]);
      await app.sync();
      expect(app.pending, 0);
      final reg = await call('GET', '/attendance/register?classId=${jss2a.id}&date=$today', token: principal);
      expect(reg['students'].firstWhere((s) => s['id'] == roll.first.id)['status'], 'LATE');
      expect(app.registerFor(app.snapshot!.classes.firstWhere((c) => c.id == jss2a.id), today).onServer, isTrue);
    }

    // Scores for every student in JSS 2B maths, then submit.
    final roll = maths.students;
    await app.saveScores(maths, {for (final s in roll) s.id: {'CA1': 15, 'CA2': 16.5, 'EXAM': 48}});
    await app.submitScores(app.snapshot!.subjects.firstWhere((s) => s.classSubjectId == maths.classSubjectId));
    await app.sync();
    expect(app.pending, 0);
    expect(app.notices, isEmpty);
    final sheet = await call('GET', '/scoresheets?classSubjectId=${maths.classSubjectId}', token: principal);
    expect(sheet['status'], 'SUBMITTED');
    expect(sheet['students'].firstWhere((s) => s['id'] == studentId)['total'], 79.5);
    expect(app.sheetFor(app.snapshot!.subjects.firstWhere((s) => s.classSubjectId == maths.classSubjectId)).status, 'SUBMITTED');

    // A change the school's rules refuse: JSS 2A maths results were released, so the server says no and the
    // teacher sees why.
    final released = app.snapshot!.subjects.firstWhere((s) => s.className == 'JSS 2A' && s.code == 'MTH');
    expect(released.released, isTrue);
    await app.saveScores(released, {released.students.first.id: {'CA1': 1, 'CA2': 1, 'EXAM': 1}});
    await app.sync();
    expect(app.pending, 0);
    expect(app.notices.single.message, 'Mathematics scores for JSS 2A was not accepted: These results have been released.');

    // The school returns the sheet; the teacher sees the note after the next sync.
    await call('POST', '/scoresheets/${sheet['id']}/return', token: principal, body: {'note': 'Check the exam marks.'});
    await app.sync();
    final v = app.sheetFor(app.snapshot!.subjects.firstWhere((s) => s.classSubjectId == maths.classSubjectId));
    expect(v.status, 'RETURNED');
    expect(v.returnNote, 'Check the exam marks.');
    expect(v.editable, isTrue);
    app.dispose();
  }, skip: !live ? 'Set EDUOS_LIVE=1 with eduos-api and eduos-sync running' : null, timeout: const Timeout(Duration(minutes: 2)));
}
