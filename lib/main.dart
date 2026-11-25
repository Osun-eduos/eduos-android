import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import 'src/app_state.dart';
import 'src/net/api.dart';
import 'src/store/local_store.dart';
import 'src/store/vault.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/login_screen.dart';
import 'src/ui/theme.dart';

// Server addresses can be set at build time, e.g.
// flutter build apk --dart-define=API_URL=https://api.eduos.example --dart-define=SYNC_URL=https://sync.eduos.example
// The defaults reach a development machine from the Android emulator.
const _apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');
const _syncUrl = String.fromEnvironment('SYNC_URL', defaultValue: 'http://10.0.2.2:4000');

Future<LocalStore> openEncryptedStore(String key) async {
  final path = p.join(await cipher.getDatabasesPath(), 'eduos.db');
  final db = await cipher.openDatabase(path, password: key, version: 1, onCreate: LocalStore.create);
  return LocalStore(db);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final vault = SecureVault();
  final servers = Servers(api: _apiUrl, sync: _syncUrl);
  final state = AppState(vault: vault, api: Api(client: http.Client(), vault: vault, servers: servers), openStore: openEncryptedStore, defaultServers: servers);
  runApp(ChangeNotifierProvider.value(value: state, child: const EduosApp()));
  state.init();
}

class EduosApp extends StatefulWidget {
  const EduosApp({super.key});
  @override
  State<EduosApp> createState() => _EduosAppState();
}

class _EduosAppState extends State<EduosApp> with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _net;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Send waiting changes as soon as a connection comes back.
    _net = Connectivity().onConnectivityChanged.listen((r) {
      if (mounted && !r.contains(ConnectivityResult.none)) context.read<AppState>().sync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _net?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) context.read<AppState>().sync();
  }

  @override
  Widget build(BuildContext context) {
    final phase = context.select<AppState, Phase>((a) => a.phase);
    return MaterialApp(
      title: 'EduOS Teacher',
      debugShowCheckedModeBanner: false,
      theme: eduosTheme(Brightness.light),
      darkTheme: eduosTheme(Brightness.dark),
      home: switch (phase) {
        Phase.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
        Phase.signedOut => const LoginScreen(),
        Phase.changePassword => const ChangePasswordScreen(),
        Phase.ready => const HomeScreen(),
      },
    );
  }
}
