import 'dart:async';
import 'dart:convert';

import 'package:eduos_mobile/main.dart' show EduosApp;
import 'package:eduos_mobile/src/app_state.dart';
import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/parent.dart';
import 'package:eduos_mobile/src/push.dart';
import 'package:eduos_mobile/src/store/local_store.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:eduos_mobile/src/sync/parent_sync.dart';
import 'package:eduos_mobile/src/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// A healthy API for a parent that remembers what was read; records every request.
MockClient parentServer(List<http.Request> seen, {bool offline = false}) {
  final read = <String>{};
  return MockClient((r) async {
    seen.add(r);
    if (offline) throw http.ClientException('No route to host');
    if (r.method == 'POST' && r.url.path == '/notifications/read') {
      read.addAll(((jsonDecode(r.body) as Map)['ids'] as List).cast<String>());
      return json({'updated': 1, 'unread': 1}, 201);
    }
    if (r.url.path == '/notifications') {
      final inbox = Map<String, dynamic>.from(
        parentApi()['/notifications'] as Map,
      );
      inbox['items'] = [
        for (final n in inbox['items'] as List)
          {...n as Map, if (read.contains(n['id'])) 'read': true},
      ];
      return json(inbox);
    }
    if (r.method == 'POST' && r.url.path == '/devices') {
      return json({'ok': true, 'push': true}, 201);
    }
    if (r.method == 'POST' && r.url.path == '/auth/login') {
      return json({
        'accessToken': 'a',
        'refreshToken': 'r',
        'user': {
          'fullName': 'Funmi Adewale',
          'role': 'PARENT',
          'mustChangePassword': false,
        },
      });
    }
    final body = parentApi()[r.url.path];
    return body == null ? json({'message': 'Not found'}, 404) : json(body);
  });
}

class FakePush extends PushRegistrar {
  final arrivalsCtl = StreamController<void>.broadcast();
  @override
  Future<String?> token() async => 'fcm-token-for-this-phone-0001';
  @override
  Stream<String> get tokenChanges => const Stream.empty();
  @override
  Stream<void> get arrivals => arrivalsCtl.stream;
  @override
  String get platform => 'android';
}

void main() {
  test(
    'downloads each child, their attendance and latest report card, and the inbox; sends offline reads first',
    () async {
      final store = await memoryStore();
      final seen = <http.Request>[];
      final vault = MemoryVault()
        ..values.addAll({'accessToken': 'a', 'refreshToken': 'r'});
      final sync = ParentSync(
        api: Api(
          client: parentServer(seen),
          vault: vault,
          servers: Servers(api: 'http://api', sync: 'http://sync'),
        ),
        store: store,
        userName: 'Funmi Adewale',
      );
      await ParentSync.addPendingReads(store, ['n-9']);
      expect((await sync.run()).outcome, SyncOutcome.synced);
      expect(seen.first.url.path, '/notifications/read');
      expect(jsonDecode(seen.first.body), {
        'ids': ['n-9'],
      });
      expect(await ParentSync.pendingReads(store), isEmpty);
      expect(
        seen
            .where((r) => r.url.path == '/report-cards/$childId')
            .single
            .url
            .queryParameters['termId'],
        termId,
      );

      final data = ParentData.fromJson(
        jsonDecode((await store.meta('parent'))!),
      );
      final c = data.children.single;
      expect(
        [
          c.firstName,
          c.className,
          c.attendance.rate,
          c.attendance.absences,
          c.latestCard?.average,
          c.latestCard?.position,
        ],
        ['Toluwani', 'JSS 1A', 95.0, 1, 71.0, '3rd'],
      );
      expect(
        c.attendance.records.first.date,
        '2026-11-25',
        reason: 'newest first',
      );
      expect(data.unread, 2);
      expect(data.inbox.first.childId, childId);

      final offline = ParentSync(
        api: Api(
          client: parentServer([], offline: true),
          vault: vault,
          servers: Servers(api: 'http://api', sync: 'http://sync'),
        ),
        store: store,
        userName: 'x',
      );
      expect((await offline.run()).outcome, SyncOutcome.offline);
      expect(
        await store.meta('parent'),
        isNotNull,
        reason: 'what was saved stays',
      );
    },
  );

  testWidgets(
    'a parent signs in, registers for push, and reads a report card from a notification',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 760));
      tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
        MockStreamHandler.inline(onListen: (_, _) {}),
      );
      sqfliteFfiInit();
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: databaseVersion,
          onCreate: LocalStore.create,
          singleInstance: false,
        ),
      );
      final store = LocalStore(db);
      final seen = <http.Request>[];
      final vault = MemoryVault();
      final servers = Servers(api: 'http://api', sync: 'http://sync');
      final push = FakePush();
      final app = AppState(
        vault: vault,
        api: Api(client: parentServer(seen), vault: vault, servers: servers),
        openStore: (_) async => store,
        defaultServers: servers,
        push: push,
      );
      await tester.runAsync(() async {
        await app.init();
        expect(await app.signIn('08031112222', 'Permanent2026'), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      expect(app.isParent, isTrue);
      expect(vault.values['role'], 'PARENT');
      final device = seen.where((r) => r.url.path == '/devices').single;
      expect(jsonDecode(device.body), {
        'token': 'fcm-token-for-this-phone-0001',
        'platform': 'android',
      });

      await tester.pumpWidget(
        ChangeNotifierProvider.value(value: app, child: const EduosApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Good day, Funmi'), findsOneWidget);
      expect(find.text('Adewale Toluwani Grace'), findsOneWidget);
      expect(find.text('95%'), findsOneWidget);
      expect(find.text('1 absent'), findsOneWidget);
      expect(find.text('3rd of 38'), findsOneWidget);
      expect(find.text('2 new notifications'), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-inbox')));
      await tester.pumpAndSettle();
      expect(find.text('Report card ready'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Report card ready'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Mathematics'), findsOneWidget);
      expect(find.text('78'), findsOneWidget);
      expect(find.text('A hard-working pupil.'), findsOneWidget);
    await tester.tap(find.text('Attendance').first);
    await tester.pumpAndSettle();
    expect(find.text('Wed 25 Nov'), findsOneWidget);
    expect(find.text('Absent'), findsWidgets);
      expect(
        await tester.runAsync(() => ParentSync.pendingReads(store)),
        anyOf(contains('n-1'), isEmpty),
        reason: 'marked read here, or already sent',
      );
      expect(
        app.parentData!.inbox.firstWhere((n) => n.id == 'n-1').read,
        isTrue,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 new notification'), findsOneWidget);

      // Signing out stops pushes to this phone for this parent.
      await tester.runAsync(() => app.signOut());
      expect(
        seen.where(
          (r) =>
              r.method == 'DELETE' &&
              r.url.path == '/devices/fcm-token-for-this-phone-0001',
        ),
        hasLength(1),
      );
      app.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    },
  );
}
