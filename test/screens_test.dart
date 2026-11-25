import 'package:eduos_mobile/main.dart' show EduosApp;
import 'package:eduos_mobile/src/app_state.dart';
import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/store/local_store.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures.dart';

/// A teacher who synced earlier and is now offline.
Future<(AppState, LocalStore)> offlineTeacher(WidgetTester tester) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: LocalStore.create, singleInstance: false));
  final store = LocalStore(db);
  await store.saveSnapshot(snapshotBody(), DateTime.utc(2026, 11, 25, 7));
  final vault = MemoryVault()..values.addAll({'accessToken': 'a', 'refreshToken': 'r'});
  final servers = Servers(api: 'http://api', sync: 'http://sync');
  final app = AppState(
    vault: vault,
    api: Api(client: MockClient((_) async => throw http.ClientException('No route to host')), vault: vault, servers: servers),
    openStore: (_) async => store,
    defaultServers: servers,
    clock: () => DateTime.utc(2026, 11, 25, 8), // Wednesday 25 Nov, 9am in Lagos
  );
  await app.init();
  await tester.pumpWidget(ChangeNotifierProvider.value(value: app, child: const EduosApp()));
  await tester.pumpAndSettle();
  return (app, store);
}

/// Stops the app's sync timer and lets snackbars close, so no timers outlive the test.
Future<void> finish(WidgetTester tester, AppState app) async {
  app.dispose();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void main() {
  testWidgets('takes a register offline and queues it for sync', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final (app, store) = await offlineTeacher(tester);
    expect(find.text('Good day, Tunde'), findsOneWidget);
    expect(find.textContaining("Today's register not taken"), findsOneWidget);

    await tester.tap(find.text('JSS 2A').first);
    await tester.pumpAndSettle();
    expect(find.text('JSS 2A register'), findsOneWidget);
    // Zaki was admitted today, so he is on today's roll.
    expect(find.text('Zaki New'), findsOneWidget);
    final save = find.byKey(const Key('save-register'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'everyone must be marked first');

    await tester.tap(find.text('Mark everyone present'));
    await tester.pump();
    await tester.tap(find.descendant(of: find.byKey(const Key('mark-s2')), matching: find.text('A')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Reason (optional)'), 'Malaria');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('Register saved on this phone'), findsOneWidget);

    final queued = await store.pending();
    expect(queued.single.type, 'attendance.register');
    expect(queued.single.label, 'JSS 2A register for Wed 25 Nov');
    final marks = (queued.single.payload['marks'] as List).cast<Map>();
    expect(marks, hasLength(3));
    expect(marks.firstWhere((m) => m['studentId'] == 's2'), {'studentId': 's2', 'status': 'ABSENT', 'note': 'Malaria'});
    expect(app.pending, 1);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('waiting to sync'), findsWidgets);
    expect(find.textContaining('1 change saved on this phone'), findsOneWidget);

    // Yesterday's register came from the server: Babalola was absent.
    await tester.tap(find.text('JSS 2A').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tue 24 Nov'));
    await tester.pumpAndSettle();
    expect(find.text('Register taken'), findsOneWidget);
    expect(find.text('Sick'), findsOneWidget);
    expect(find.text('Zaki New'), findsNothing, reason: 'not yet admitted on the 24th');
    await finish(tester, app);
  });

  testWidgets('enters scores one student at a time, rejecting impossible marks', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final (app, store) = await offlineTeacher(tester);
    await tester.tap(find.text('Mathematics'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 complete'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);

    await tester.tap(find.text('Babalola Tunde'));
    await tester.pumpAndSettle();
    expect(find.text('Student 2 of 3'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('s2-CA1')), '25');
    await tester.pump();
    expect(find.text('0 to 20'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('s2-CA1')), '15');
    await tester.enterText(find.byKey(const Key('s2-CA2')), '14.5');
    await tester.enterText(find.byKey(const Key('s2-EXAM')), '45');
    await tester.pump();
    expect(find.text('74.5 / 100'), findsOneWidget);
    expect(find.text('A · Excellent'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2 of 3 complete'), findsOneWidget);
    final submit = find.widgetWithText(FilledButton, 'Submit for approval');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull, reason: 'Zaki has no marks yet');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pumpAndSettle();
    final queued = await store.pending();
    expect(queued.single.type, 'scores.save');
    expect(queued.single.payload, {
      'classSubjectId': mathsId,
      'scores': [
        {'studentId': 's2', 'marks': {'CA1': 15.0, 'CA2': 14.5, 'EXAM': 45.0}},
      ],
    });
    expect(find.text('Draft'), findsOneWidget);
    await finish(tester, app);
  });

  testWidgets('locks released results', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    final (_, store) = await offlineTeacher(tester);
    await store.saveSnapshot(snapshotBody(released: true, sheetStatus: 'APPROVED'), DateTime.now());
    final app = tester.element(find.byType(Scaffold).first).read<AppState>();
    await app.reload();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mathematics'));
    await tester.pumpAndSettle();
    expect(find.text('These results have been released.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit for approval'), findsNothing);
    await finish(tester, app);
  });
}
