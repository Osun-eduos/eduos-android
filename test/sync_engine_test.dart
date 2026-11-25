import 'dart:convert';

import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/store/local_store.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:eduos_mobile/src/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

OutboxEvent ev(String id, {String key = 'reg:c:2026-11-25', String type = 'attendance.register'}) =>
    OutboxEvent(id: id, type: type, payload: {'classId': 'c'}, occurredAt: DateTime.utc(2026, 11, 25, 8), draftKey: key, label: 'JSS 2A register for Wed 25 Nov');

void main() {
  late LocalStore store;
  late MemoryVault vault;
  late List<http.Request> requests;

  setUp(() async {
    store = await memoryStore();
    vault = MemoryVault()..values.addAll({'accessToken': 'old', 'refreshToken': 'rt1'});
    requests = [];
  });

  SyncEngine engine(Future<http.Response> Function(http.Request r) handler) {
    final api = Api(client: MockClient((r) async {
      requests.add(r);
      return handler(r);
    }), vault: vault, servers: Servers(api: 'http://api', sync: 'http://sync'));
    return SyncEngine(api: api, store: store, deviceId: 'phone-test');
  }

  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
  http.Response results(http.Request r, String Function(String id) status, {String? message}) {
    final events = (jsonDecode(r.body)['events'] as List).cast<Map<String, dynamic>>();
    return json({'results': [for (final e in events) {'id': e['id'], 'status': status(e['id']), 'message': ?message}]});
  }

  test('sends queued changes in order, then downloads a snapshot and clears confirmed drafts', () async {
    await store.record(draftKey: 'reg:c:2026-11-25', draft: {'marks': []}, event: ev('e1'));
    await store.record(draftKey: 'scores:m', draft: {'marks': {}}, event: ev('e2', key: 'scores:m', type: 'scores.save'));
    final r = await engine((req) async => req.url.path == '/v1/sync' ? results(req, (_) => 'applied') : json(snapshotBody())).run();
    expect(r.outcome, SyncOutcome.synced);
    expect(r.applied, 2);
    final sent = jsonDecode(requests.first.body)['events'] as List;
    expect(sent.map((e) => e['id']), ['e1', 'e2']);
    expect(sent.first.containsKey('label'), isFalse, reason: 'the label stays on the phone');
    expect(requests.first.headers['X-Device-Id'], 'phone-test');
    expect(requests.first.headers['Authorization'], 'Bearer old');
    expect(await store.pendingCount(), 0);
    expect(await store.drafts(), isEmpty);
    expect((await store.snapshotJson())!['snapshot']['user']['fullName'], 'Tunde Olaniyan');
    expect(await store.lastSyncAt(), isNotNull);
  });

  test('a refused change is dropped with its draft, and the teacher is told why', () async {
    await store.record(draftKey: 'reg:c:2026-11-10', draft: {'marks': []}, event: ev('e1', key: 'reg:c:2026-11-10'));
    await store.record(draftKey: 'reg:c:2026-11-25', draft: {'marks': []}, event: ev('e2'));
    final r = await engine((req) async => req.url.path == '/v1/sync'
        ? json({'results': [
            {'id': 'e1', 'status': 'rejected', 'message': 'Class teachers can change registers for the last 7 days.'},
            {'id': 'e2', 'status': 'applied'},
          ]})
        : json(snapshotBody())).run();
    expect(r.rejected, 1);
    final notices = await store.notices();
    expect(notices.single.message, 'JSS 2A register for Wed 25 Nov was not accepted: Class teachers can change registers for the last 7 days.');
    expect(await store.draft('reg:c:2026-11-10'), isNull);
  });

  test('keeps the queue in order when the server says retry, and does not download', () async {
    await store.record(draftKey: 'a', draft: {}, event: ev('e1', key: 'a'));
    await store.record(draftKey: 'b', draft: {}, event: ev('e2', key: 'b'));
    await store.record(draftKey: 'c', draft: {}, event: ev('e3', key: 'c'));
    final r = await engine((req) async => json({'results': [
          {'id': 'e1', 'status': 'applied'},
          {'id': 'e2', 'status': 'retry', 'message': 'busy'},
          {'id': 'e3', 'status': 'retry'},
        ]})).run();
    expect(r.outcome, SyncOutcome.offline);
    expect((await store.pending()).map((e) => e.id), ['e2', 'e3']);
    expect((await store.pending()).first.attempts, 1);
    expect(requests.where((q) => q.url.path == '/v1/snapshot'), isEmpty);
  });

  test('works offline: nothing is lost when there is no connection', () async {
    await store.record(draftKey: 'a', draft: {}, event: ev('e1', key: 'a'));
    final r = await engine((req) async => throw http.ClientException('Failed host lookup')).run();
    expect(r.outcome, SyncOutcome.offline);
    expect(r.waiting, 1);
    expect(r.message, contains('saved on this phone'));
    expect(await store.draft('a'), isNotNull);
  });

  test('refreshes an expired access token once and carries on', () async {
    await store.record(draftKey: 'a', draft: {}, event: ev('e1', key: 'a'));
    var syncCalls = 0;
    final r = await engine((req) async {
      if (req.url.path == '/auth/refresh') {
        expect(jsonDecode(req.body)['refreshToken'], 'rt1');
        expect(req.headers['X-Client'], 'mobile');
        return json({'accessToken': 'new', 'refreshToken': 'rt2', 'user': {}});
      }
      if (req.url.path == '/v1/sync') {
        syncCalls++;
        if (req.headers['Authorization'] == 'Bearer old') return json({'message': 'expired'}, 401);
        return results(req, (_) => 'applied');
      }
      return json(snapshotBody());
    }).run();
    expect(r.outcome, SyncOutcome.synced);
    expect(syncCalls, 2);
    expect(vault.values['accessToken'], 'new');
    expect(vault.values['refreshToken'], 'rt2');
  });

  test('asks the teacher to sign in again when the refresh token is no longer valid, keeping changes', () async {
    await store.record(draftKey: 'a', draft: {}, event: ev('e1', key: 'a'));
    final r = await engine((req) async => json({'message': 'Please sign in.'}, 401)).run();
    expect(r.outcome, SyncOutcome.signedOut);
    expect(await store.pendingCount(), 1);
  });

  test('sends large queues in batches', () async {
    for (var i = 0; i < 120; i++) {
      await store.record(draftKey: 'k$i', draft: {}, event: ev('e$i', key: 'k$i'));
    }
    final r = await engine((req) async => req.url.path == '/v1/sync' ? results(req, (_) => 'applied') : json(snapshotBody())).run();
    expect(r.applied, 120);
    expect(requests.where((q) => q.url.path == '/v1/sync').length, 3);
  });
}
