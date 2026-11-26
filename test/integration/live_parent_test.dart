// End-to-end check of parent mode against a running eduos-api with the walkthrough data (Mrs Funmi Adewale,
// 08031112222, a parent at Osogbo Grammar School). Skipped unless EDUOS_LIVE=1.
// Run: EDUOS_LIVE=1 flutter test test/integration/live_parent_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:eduos_mobile/src/app_state.dart';
import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/store/local_store.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final live = Platform.environment['EDUOS_LIVE'] == '1';
final apiUrl = Platform.environment['EDUOS_API_URL'] ?? 'http://localhost:3000';

Future<String> login(String id) async =>
    jsonDecode((await http.post(Uri.parse('$apiUrl/auth/login'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'identifier': id, 'password': 'Permanent2026'}))).body)['accessToken'];

void main() {
  test('a school notice reaches the parent app, and reading it there clears it on the server', () async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final head = await login('head@osogbo.test');
    final sent = await http.post(Uri.parse('$apiUrl/notices'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $head'}, body: jsonEncode({'title': 'Live test $stamp', 'body': 'From the live test.'}));
    expect(sent.statusCode, 201, reason: sent.body);

    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: databaseVersion, onCreate: LocalStore.create, singleInstance: false));
    final vault = MemoryVault();
    final servers = Servers(api: apiUrl, sync: 'http://unused');
    final app = AppState(vault: vault, api: Api(client: http.Client(), vault: vault, servers: servers), openStore: (_) async => LocalStore(db), defaultServers: servers);
    await app.init();
    expect(await app.signIn('08031112222', 'Permanent2026'), isNull);
    expect(app.isParent, isTrue);
    expect(app.parentData!.children.map((c) => c.firstName), containsAll(['Toluwani', 'Kunle']));
    final n = app.parentData!.inbox.firstWhere((x) => x.title == 'Live test $stamp');
    expect(n.read, isFalse);
    await app.markRead([n.id]);
    await app.sync();
    final parent = await login('08031112222');
    final inbox = jsonDecode((await http.get(Uri.parse('$apiUrl/notifications'), headers: {'Authorization': 'Bearer $parent'})).body);
    expect((inbox['items'] as List).firstWhere((x) => x['id'] == n.id)['read'], isTrue);
    app.dispose();
  }, skip: live ? false : 'Set EDUOS_LIVE=1 with eduos-api running');
}
