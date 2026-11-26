// End-to-end check of the inspector flow against a running eduos-api with the walkthrough data
// (an LGA officer kola@lga.test in Osogbo). Skipped unless EDUOS_LIVE=1.
// Run: EDUOS_LIVE=1 flutter test test/integration/live_inspector_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:eduos_mobile/src/app_state.dart';
import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/store/local_store.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fixtures.dart';

final live = Platform.environment['EDUOS_LIVE'] == '1';
final apiUrl = Platform.environment['EDUOS_API_URL'] ?? 'http://localhost:3000';

void main() {
  test('an LGA officer records an inspection with a photo, and the Ministry sees it', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: databaseVersion, onCreate: LocalStore.create, singleInstance: false));
    final store = LocalStore(db);
    final tmp = await Directory.systemTemp.createTemp('eduos-live');
    final vault = MemoryVault();
    final servers = Servers(api: apiUrl, sync: 'http://unused');
    final app = AppState(vault: vault, api: Api(client: http.Client(), vault: vault, servers: servers), openStore: (_) async => store, defaultServers: servers, photosDir: () async => Directory('${tmp.path}/kept'));
    await app.init();

    expect(await app.signIn('kola@lga.test', 'Permanent2026'), isNull);
    expect(app.isInspector, isTrue);
    final school = app.inspector!.schools.firstWhere((s) => s.name == 'Osogbo Grammar School');
    expect(app.inspector!.schools.every((s) => s.lga == 'Osogbo'), isTrue);
    expect(app.inspector!.checklist.sections, hasLength(6));

    final id = await app.startInspection(school);
    final i = (await store.inspection(id))!;
    i.answers.addAll(goodAnswers());
    i.answers['classrooms']!['roofLeaks'] = true;
    i.notes = 'Live test from the app.';
    await app.saveInspection(i);
    final jpeg = File('${tmp.path}/roof.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xe0, ...List.filled(4000, 9)]);
    await app.addPhoto(id, 'classrooms', jpeg.path, caption: 'Leaking roof');
    await app.submitInspection(id);
    await app.sync();
    expect(app.pending, 0, reason: app.syncMessage);

    final sent = (await store.inspection(id))!;
    expect([sent.status, sent.overall], ['sent', 'POOR']);
    final admin = jsonDecode((await http.post(Uri.parse('$apiUrl/auth/login'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'identifier': 'admin@moe.test', 'password': 'Permanent2026'}))).body)['accessToken'];
    final detail = jsonDecode((await http.get(Uri.parse('$apiUrl/inspections/${sent.serverId}'), headers: {'Authorization': 'Bearer $admin'})).body);
    expect(detail['notes'], 'Live test from the app.');
    expect(detail['photos'], [isA<Map>().having((p) => p['caption'], 'caption', 'Leaking roof')]);
    final img = await http.get(Uri.parse('$apiUrl/inspections/photos/${detail['photos'][0]['id']}'), headers: {'Authorization': 'Bearer $admin'});
    expect(img.bodyBytes.length, 4004);
    app.dispose();
    await tmp.delete(recursive: true);
  }, skip: live ? false : 'Set EDUOS_LIVE=1 with eduos-api running');
}
