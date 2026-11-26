import 'dart:convert';
import 'dart:io';

import 'package:eduos_mobile/main.dart' show EduosApp;
import 'package:eduos_mobile/src/app_state.dart';
import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/store/local_store.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:eduos_mobile/src/ui/inspector_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'checklist_fixture.dart';
import 'fixtures.dart';

void main() {
  testWidgets('an inspector records a visit with a photo while offline', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    // The connection watcher is a phone plugin; give the test a silent one.
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('dev.fluttercommunity.plus/connectivity_status'), MockStreamHandler.inline(onListen: (_, _) {}));
    sqfliteFfiInit();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: databaseVersion, onCreate: LocalStore.create, singleInstance: false));
    final store = LocalStore(db);
    await store.setMeta('inspector', jsonEncode(inspectorMeta(checklistJson)));
    final vault = MemoryVault()..values.addAll({'accessToken': 'a', 'refreshToken': 'r', 'role': 'INSPECTOR', 'lga': 'Osogbo'});
    final servers = Servers(api: 'http://api', sync: 'http://sync');
    final photos = await tester.runAsync(() => Directory.systemTemp.createTemp('eduos-photos'));
    final camera = await tester.runAsync(() async => File('${photos!.path}/camera.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]));
    takePhoto = (_) async => camera!.path;
    final app = AppState(
      vault: vault,
      api: Api(client: MockClient((_) async => throw http.ClientException('No route to host')), vault: vault, servers: servers),
      openStore: (_) async => store,
      defaultServers: servers,
      photosDir: () async => Directory('${photos!.path}/kept'),
      clock: () => DateTime.utc(2026, 11, 25, 8),
    );
    await app.init();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: app, child: const EduosApp()));
    await tester.pumpAndSettle();

    expect(find.text('Good day, Kola'), findsOneWidget);
    expect(find.textContaining('School inspector · Osogbo LGA · 2 schools'), findsOneWidget);
    expect(find.text('Baptist High School'), findsOneWidget);
    expect(find.text('Fair'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-inspection')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('school-search')), 'grammar');
    await tester.pump();
    expect(find.text('Baptist High School'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.text('Osogbo Grammar School'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('Visited Wed 25 Nov 2026'), findsOneWidget);
    final submit = find.byKey(const Key('submit-inspection'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.text('Classrooms: 6 questions not answered'), findsOneWidget);

    // File access needs real time; the screen needs pumping in between.
    Future<void> settleIo() async {
      for (var n = 0; n < 15; n++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump();
      }
    }

    Future<void> show(Finder f) => tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    for (final s in (checklistJson['sections'] as List).cast<Map<String, dynamic>>()) {
      for (final i in (s['items'] as List).cast<Map<String, dynamic>>()) {
        final k = '${s['key']}-${i['key']}';
        switch (i['type']) {
          case 'count':
            await show(find.byKey(Key('count-$k')));
            await tester.enterText(find.byKey(Key('count-$k')), '3');
          case 'yesno':
            await show(find.byKey(Key('yesno-$k')));
            await tester.tap(find.descendant(of: find.byKey(Key('yesno-$k')), matching: find.text('No')));
          default:
            final first = i['type'] == 'rating' ? 'GOOD' : (i['options'] as List).last['value'];
            await show(find.byKey(Key('choice-$k-$first')));
            await tester.tap(find.byKey(Key('choice-$k-$first')));
        }
        await tester.pump();
      }
    }
    await tester.scrollUntilVisible(find.byKey(const Key('photo-classrooms')), -300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('photo-classrooms')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await settleIo();
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget, reason: 'the photo shows as a thumbnail');
    await show(find.byKey(const Key('inspection-notes')));
    await tester.enterText(find.byKey(const Key('inspection-notes')), 'Roof over JSS 2 leaks.');
    await tester.pump();

    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await settleIo();
    await tester.pumpAndSettle();

    expect(find.textContaining('Submitted, waiting to sync'), findsOneWidget);
    expect(find.textContaining('2 changes saved on this phone'), findsOneWidget, reason: 'the inspection and its photo');
    final saved = (await tester.runAsync(() => store.inspections()))!.single;
    expect([saved.status, saved.schoolId, saved.notes], ['queued', 'sch-1', 'Roof over JSS 2 leaks.']);
    expect(saved.answers['classrooms'], {'total': 3, 'usable': 3, 'condition': 'GOOD', 'roofLeaks': false, 'enoughSeats': false, 'boards': 'GOOD'});
    expect(saved.answers['water']!['source'], 'RAIN');
    final photo = (await tester.runAsync(() => store.photos()))!.single;
    expect([photo.section, photo.status, photo.inspectionId], ['classrooms', 'queued', saved.clientId]);
    expect(File(photo.path).existsSync(), isTrue, reason: 'a copy is kept in the app folder until it is sent');

    app.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(() => photos!.delete(recursive: true));
  });
}
