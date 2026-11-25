import 'dart:convert';
import 'dart:io';

import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/store/local_store.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:eduos_mobile/src/sync/background.dart';
import 'package:eduos_mobile/src/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

void main() {
  late Directory dir;
  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('eduos-bg');
  });
  tearDown(() => dir.delete(recursive: true));

  // A database file, so the background run can open and close it like the real one.
  Future<LocalStore> open(String _) async => LocalStore(await databaseFactoryFfi.openDatabase('${dir.path}/eduos.db',
      options: OpenDatabaseOptions(version: 1, onCreate: LocalStore.create, singleInstance: false)));

  test('does nothing when nobody is signed in', () async {
    expect(await backgroundSync(MemoryVault(), Servers(api: 'http://a', sync: 'http://s'), openStore: open), isNull);
  });

  test('sends changes queued while the app was closed, then refreshes the snapshot', () async {
    final first = await open('');
    await first.record(
      draftKey: 'reg:c:2026-11-25',
      draft: {'marks': []},
      event: OutboxEvent(id: 'e1', type: 'attendance.register', payload: {'classId': 'c'}, occurredAt: DateTime.now(), draftKey: 'reg:c:2026-11-25', label: 'JSS 2A register'),
    );
    await first.db.close();

    final vault = MemoryVault()..values.addAll({'refreshToken': 'r', 'accessToken': 'a', 'apiUrl': 'http://api', 'syncUrl': 'http://sync'});
    final seen = <String>[];
    final client = MockClient((req) async {
      seen.add('${req.method} ${req.url}');
      if (req.url.path == '/v1/sync') {
        final ids = (jsonDecode(req.body)['events'] as List).map((e) => e['id']);
        return http.Response(jsonEncode({'results': [for (final id in ids) {'id': id, 'status': 'applied'}]}), 200);
      }
      return http.Response(jsonEncode(snapshotBody()), 200);
    });
    final r = await backgroundSync(vault, null, openStore: open, client: client);
    expect(r!.outcome, SyncOutcome.synced);
    expect(seen, ['POST http://sync/v1/sync', 'GET http://sync/v1/snapshot'], reason: 'uses the addresses the teacher signed in with');

    final after = await open('');
    expect(await after.pendingCount(), 0);
    expect(await after.snapshotJson(), isNotNull);
    await after.db.close();
  });
}
