import 'dart:convert';
import 'dart:io';

import 'package:eduos_mobile/src/inspection.dart';
import 'package:eduos_mobile/src/net/api.dart';
import 'package:eduos_mobile/src/store/local_store.dart';
import 'package:eduos_mobile/src/store/vault.dart';
import 'package:eduos_mobile/src/sync/inspection_sync.dart';
import 'package:eduos_mobile/src/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'checklist_fixture.dart';
import 'fixtures.dart';

void main() {
  late LocalStore store;
  late MemoryVault vault;
  late List<http.Request> requests;
  late Directory tmp;
  final jpeg = [0xff, 0xd8, 0xff, 0xe0, ...List.filled(500, 7)];

  setUp(() async {
    store = await memoryStore();
    vault = MemoryVault()..values.addAll({'accessToken': 'old', 'refreshToken': 'rt1'});
    requests = [];
    tmp = await Directory.systemTemp.createTemp('eduos-test');
  });
  tearDown(() => tmp.delete(recursive: true));

  http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  InspectionSync engine(Future<http.Response> Function(http.Request r) handler) => InspectionSync(
        api: Api(client: MockClient((r) async {
          requests.add(r);
          return handler(r);
        }), vault: vault, servers: Servers(api: 'http://api', sync: 'http://sync')),
        store: store,
        userName: 'Kola Adeyemi',
        lga: 'Osogbo',
      );

  /// A healthy server: accepts the inspection and photos, and serves the inspector's work set.
  Future<http.Response> server(http.Request r) async {
    final p = r.url.path;
    if (r.method == 'POST' && p == '/inspections') return json({'id': 'srv-1', 'overall': 'POOR', 'clientId': jsonDecode(r.body)['clientId']}, 201);
    if (r.method == 'POST' && p == '/inspections/srv-1/photos') return json({'id': 'ph-1'}, 201);
    if (p == '/schools/directory') return json((inspectorMeta(checklistJson)['schools'] as List));
    if (p == '/inspections/template') return json(checklistJson);
    if (p == '/inspections') return json([{'id': 'srv-1', 'clientId': 'insp-1', 'school': {'name': 'Osogbo Grammar School'}, 'visitedOn': '2026-11-25', 'overall': 'POOR', 'issues': [], 'photoCount': 1}]);
    return json({'message': 'Not found'}, 404);
  }

  Future<void> queued({String status = 'queued'}) async {
    await store.saveInspection(LocalInspection(clientId: 'insp-1', schoolId: 'sch-1', schoolName: 'Osogbo Grammar School', visitedOn: '2026-11-25', answers: goodAnswers(), notes: ' Roof leaks ', actionNeeded: 'Repair the roof ', status: status));
    final f = File('${tmp.path}/p1.jpg')..writeAsBytesSync(jpeg);
    await store.savePhoto(LocalPhoto(clientId: 'photo-1', inspectionId: 'insp-1', section: 'classrooms', path: f.path, caption: 'JSS 2 roof'));
  }

  test('sends a submitted inspection, then its photo, then refreshes the schools and checklist', () async {
    await queued();
    expect(await store.inspectionsWaiting(), 2);
    final r = await engine(server).run();
    expect(r.outcome, SyncOutcome.synced);
    expect(r.applied, 2);

    final post = requests.firstWhere((x) => x.url.path == '/inspections' && x.method == 'POST');
    expect(jsonDecode(post.body), {'clientId': 'insp-1', 'schoolId': 'sch-1', 'visitedOn': '2026-11-25', 'answers': goodAnswers(), 'notes': 'Roof leaks', 'actionNeeded': 'Repair the roof'});
    expect(post.headers['Authorization'], 'Bearer old');
    final upload = requests.firstWhere((x) => x.url.path.endsWith('/photos'));
    expect(upload.headers['content-type'], startsWith('multipart/form-data'));
    final form = latin1.decode(upload.bodyBytes);
    expect(form, contains('name="clientId"\r\n\r\nphoto-1'));
    expect(form, contains('name="section"\r\n\r\nclassrooms'));
    expect(form, contains('name="photo"; filename="p1.jpg"'));

    final i = (await store.inspection('insp-1'))!;
    expect([i.status, i.serverId, i.overall], ['sent', 'srv-1', 'POOR']);
    expect((await store.photos()).single.status, 'sent');
    expect(File('${tmp.path}/p1.jpg').existsSync(), isFalse, reason: 'sent photos are removed from the phone');
    final meta = InspectorData.fromJson(jsonDecode((await store.meta('inspector'))!));
    expect([meta.schools.length, meta.checklist.sections.length, meta.recent.single.overall, meta.lga], [2, 6, 'POOR', 'Osogbo']);
    expect(await store.inspectionsWaiting(), 0);
  });

  test('keeps everything when there is no connection, and does not send drafts', () async {
    await queued(status: 'draft');
    final r = await engine((_) async => throw http.ClientException('No route to host')).run();
    expect(r.outcome, SyncOutcome.offline);
    expect(requests.where((x) => x.method == 'POST'), isEmpty, reason: 'a draft is not sent');
    expect((await store.inspection('insp-1'))!.status, 'draft');
    expect(File('${tmp.path}/p1.jpg').existsSync(), isTrue);
  });

  test('sends the photo later if the connection drops after the inspection', () async {
    await queued();
    var photosDown = true;
    Future<http.Response> flaky(http.Request r) async {
      if (r.url.path.endsWith('/photos') && photosDown) throw http.ClientException('Connection reset');
      return server(r);
    }
    expect((await engine(flaky).run()).outcome, SyncOutcome.offline);
    expect((await store.inspection('insp-1'))!.status, 'sent');
    expect((await store.photos()).single.status, 'queued');
    photosDown = false;
    expect((await engine(flaky).run()).outcome, SyncOutcome.synced);
    expect(requests.where((x) => x.method == 'POST' && x.url.path == '/inspections'), hasLength(1), reason: 'the inspection is not sent twice');
    expect((await store.photos()).single.status, 'sent');
  });

  test('tells the inspector when the server refuses an inspection, and signs in again on an expired token', () async {
    await queued();
    var calls = 0;
    final r = await engine((req) async {
      if (req.url.path == '/auth/refresh') return json({'accessToken': 'new', 'refreshToken': 'rt2'});
      if (req.method == 'POST' && req.url.path == '/inspections') {
        if (calls++ == 0) return json({'message': 'Token expired'}, 401);
        return json({'message': 'School not found.'}, 404);
      }
      return server(req);
    }).run();
    expect(r.outcome, SyncOutcome.synced);
    expect(r.rejected, 1);
    expect(vault.values['accessToken'], 'new');
    final i = (await store.inspection('insp-1'))!;
    expect([i.status, i.error], ['failed', 'School not found.']);
    expect((await store.notices()).single.message, 'The inspection of Osogbo Grammar School was not accepted: School not found.');
    expect((await store.photos()).single.status, 'queued', reason: 'its photo has nowhere to go');
  });

  test('lists what is missing before an inspection can be submitted', () {
    final c = Checklist.fromJson(checklistJson);
    expect(c.problems(goodAnswers()), isEmpty);
    final a = goodAnswers()..remove('water');
    a['power']!.remove('working');
    expect(c.problems(a), ['Water: 3 questions not answered', 'Power: 1 question not answered']);
    final b = goodAnswers();
    b['toilets']!['working'] = 11;
    expect(c.problems(b), ['Toilets: more working toilets than toilets']);
  });

  test('adds the inspection tables to a phone that has the older database', () async {
    sqfliteFfiInit();
    final path = '${tmp.path}/old.db';
    final v1 = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
      for (final s in schema.where((s) => !inspectionSchema.contains(s))) {
        await db.execute(s);
      }
    }));
    await v1.insert('meta', {'key': 'snapshot', 'value': '{}'});
    await v1.close();
    final v2 = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: databaseVersion, onCreate: LocalStore.create, onUpgrade: LocalStore.upgrade));
    final s = LocalStore(v2);
    expect(await s.meta('snapshot'), '{}', reason: 'existing data is kept');
    await s.saveInspection(LocalInspection(clientId: 'x', schoolId: 's', schoolName: 'S', visitedOn: '2026-11-25', answers: {}));
    expect((await s.inspections()).single.clientId, 'x');
    await v2.close();
  });

  test('adds "action needed" to a phone on database version 2, keeping saved inspections', () async {
    sqfliteFfiInit();
    final path = '${tmp.path}/v2.db';
    final v2 = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 2, onCreate: (db, _) async {
      for (final s in schema.where((s) => !inspectionSchema.contains(s))) {
        await db.execute(s);
      }
      await db.execute(inspectionSchema.first.replaceFirst(' action_needed TEXT,', ''));
      await db.execute(inspectionSchema.last);
    }));
    await v2.insert('inspections', {'client_id': 'old', 'school_id': 's', 'school_name': 'S', 'visited_on': '2026-11-20', 'answers': '{}', 'status': 'draft', 'updated_at': '2026-11-20T10:00:00Z'});
    await v2.close();
    final v3 = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: databaseVersion, onCreate: LocalStore.create, onUpgrade: LocalStore.upgrade));
    final s = LocalStore(v3);
    final old = (await s.inspections()).single;
    expect([old.clientId, old.actionNeeded], ['old', null]);
    old.actionNeeded = 'Repair the roof';
    await s.saveInspection(old);
    expect((await s.inspections()).single.actionNeeded, 'Repair the roof');
    await v3.close();
  });
}
