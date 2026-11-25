// Sync while the app is closed: Android WorkManager and iOS BGTaskScheduler run this about every 30 minutes
// when the phone has a connection (the operating system decides the exact time to save battery).
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import '../net/api.dart';
import '../store/local_store.dart';
import '../store/open.dart';
import '../store/vault.dart';
import 'sync_engine.dart';

/// Must match BGTaskSchedulerPermittedIdentifiers in ios/Runner/Info.plist and AppDelegate.swift.
const backgroundSyncTask = 'org.osuneduos.teacher.sync';

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final defaults = input == null ? null : Servers(api: input['api'] as String, sync: input['sync'] as String);
    final r = await backgroundSync(SecureVault(), defaults);
    // Returning false asks the system to retry later; only do that when the server could not be reached.
    return r == null || r.outcome != SyncOutcome.offline;
  });
}

/// One sync run outside the app. Returns null when nobody is signed in.
Future<SyncReport?> backgroundSync(
  Vault vault,
  Servers? defaults, {
  Future<LocalStore> Function(String key) openStore = openEncryptedStore,
  http.Client? client,
}) async {
  if (await vault.read('refreshToken') == null) return null;
  final apiUrl = await vault.read('apiUrl') ?? defaults?.api;
  final syncUrl = await vault.read('syncUrl') ?? defaults?.sync;
  if (apiUrl == null || syncUrl == null) return null;
  final store = await openStore(await databaseKey(vault));
  final http_ = client ?? http.Client();
  try {
    final engine = SyncEngine(api: Api(client: http_, vault: vault, servers: Servers(api: apiUrl, sync: syncUrl)), store: store, deviceId: await deviceId(vault));
    return await engine.run();
  } finally {
    if (client == null) http_.close();
    await store.db.close();
  }
}

/// Starts (or keeps) the periodic background sync. Called after sign-in and when the app starts signed in.
Future<void> scheduleBackgroundSync(Servers servers) async {
  await Workmanager().initialize(backgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundSyncTask,
    backgroundSyncTask,
    frequency: const Duration(minutes: 30),
    initialDelay: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    inputData: {'api': servers.api, 'sync': servers.sync},
  );
}

Future<void> cancelBackgroundSync() => Workmanager().cancelAll();
