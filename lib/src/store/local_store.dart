// The phone's local data: the last snapshot, unsent changes (the outbox), drafts that overlay the snapshot until
// the server confirms them, and notices about changes the server refused. On the phone it lives in an
// SQLCipher-encrypted database; the key is generated on the device and kept in the Android Keystore / iOS Keychain.
import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common/utils/utils.dart' as utils;

class OutboxEvent {
  OutboxEvent({required this.id, required this.type, required this.payload, required this.occurredAt, required this.draftKey, required this.label, this.attempts = 0, this.lastError});
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime occurredAt;
  final String draftKey;
  /// What the change was, in words for the teacher, e.g. "JSS 2A register for Tue 25 Nov". Never sent.
  final String label;
  final int attempts;
  final String? lastError;

  Map<String, dynamic> toWire() => {'id': id, 'type': type, 'occurredAt': occurredAt.toUtc().toIso8601String(), 'payload': payload};
}

class Notice {
  Notice({required this.id, required this.message, required this.createdAt});
  final int id;
  final String message;
  final DateTime createdAt;
}

class Draft {
  Draft({required this.key, required this.data, required this.updatedAt});
  final String key;
  final Map<String, dynamic> data;
  final DateTime updatedAt;
}

const schema = [
  'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, type TEXT NOT NULL, payload TEXT NOT NULL, occurred_at TEXT NOT NULL, draft_key TEXT NOT NULL, label TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT)',
  'CREATE TABLE drafts (key TEXT PRIMARY KEY, data TEXT NOT NULL, updated_at TEXT NOT NULL)',
  'CREATE TABLE notices (id INTEGER PRIMARY KEY AUTOINCREMENT, message TEXT NOT NULL, created_at TEXT NOT NULL)',
  ...inspectionSchema,
];

/// Added in database version 2: inspections recorded on this phone and their photos (files in the app's folder).
/// An inspection is a draft until submitted, then queued until the API has it; photos follow once it is sent.
const inspectionSchema = [
  'CREATE TABLE inspections (client_id TEXT PRIMARY KEY, school_id TEXT NOT NULL, school_name TEXT NOT NULL, visited_on TEXT NOT NULL, answers TEXT NOT NULL, notes TEXT, status TEXT NOT NULL, server_id TEXT, overall TEXT, error TEXT, updated_at TEXT NOT NULL)',
  'CREATE TABLE inspection_photos (client_id TEXT PRIMARY KEY, inspection_id TEXT NOT NULL, section TEXT NOT NULL, caption TEXT, path TEXT NOT NULL, status TEXT NOT NULL, error TEXT, created_at TEXT NOT NULL)',
];
const databaseVersion = 2;

class LocalStore {
  LocalStore(this.db);
  final Database db;

  static Future<void> create(Database db, int version) async {
    for (final s in schema) {
      await db.execute(s);
    }
  }

  static Future<void> upgrade(Database db, int from, int to) async {
    if (from < 2) {
      for (final s in inspectionSchema) {
        await db.execute(s);
      }
    }
  }

  Future<String?> meta(String key) async {
    final r = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) =>
      db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Map<String, dynamic>?> snapshotJson() async {
    final s = await meta('snapshot');
    return s == null ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  Future<void> saveSnapshot(Map<String, dynamic> body, DateTime at) async {
    await setMeta('snapshot', jsonEncode(body));
    await setMeta('lastSyncAt', at.toUtc().toIso8601String());
  }

  Future<DateTime?> lastSyncAt() async => DateTime.tryParse(await meta('lastSyncAt') ?? '');

  /// Saves a draft and queues the change that sends it, in one transaction.
  Future<void> record({required String draftKey, required Map<String, dynamic> draft, required OutboxEvent event}) async {
    await db.transaction((tx) async {
      await tx.insert('drafts', {'key': draftKey, 'data': jsonEncode(draft), 'updated_at': DateTime.now().toUtc().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.insert('outbox', {
        'id': event.id,
        'type': event.type,
        'payload': jsonEncode(event.payload),
        'occurred_at': event.occurredAt.toUtc().toIso8601String(),
        'draft_key': draftKey,
        'label': event.label,
      });
    });
  }

  Future<Draft?> draft(String key) async {
    final r = await db.query('drafts', where: 'key = ?', whereArgs: [key]);
    if (r.isEmpty) return null;
    return Draft(key: key, data: jsonDecode(r.first['data'] as String), updatedAt: DateTime.parse(r.first['updated_at'] as String));
  }

  Future<List<Draft>> drafts() async => (await db.query('drafts'))
      .map((r) => Draft(key: r['key'] as String, data: jsonDecode(r['data'] as String), updatedAt: DateTime.parse(r['updated_at'] as String)))
      .toList();

  Future<List<OutboxEvent>> pending({int limit = 1000}) async => (await db.query('outbox', orderBy: 'seq', limit: limit))
      .map((r) => OutboxEvent(
            id: r['id'] as String,
            type: r['type'] as String,
            payload: jsonDecode(r['payload'] as String),
            occurredAt: DateTime.parse(r['occurred_at'] as String),
            draftKey: r['draft_key'] as String,
            label: r['label'] as String,
            attempts: r['attempts'] as int,
            lastError: r['last_error'] as String?,
          ))
      .toList();

  Future<int> pendingCount() async => utils.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  Future<Set<String>> pendingDraftKeys() async =>
      (await db.rawQuery('SELECT DISTINCT draft_key FROM outbox')).map((r) => r['draft_key'] as String).toSet();

  Future<void> removeEvent(String id) => db.delete('outbox', where: 'id = ?', whereArgs: [id]);

  Future<void> markAttempt(String id, String error) =>
      db.rawUpdate('UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?', [error, id]);

  /// A change the server refused: drop it and every queued change for the same draft, drop the draft (the
  /// server's copy stands), and tell the teacher why.
  Future<void> reject(OutboxEvent e, String message) async {
    await db.transaction((tx) async {
      await tx.delete('outbox', where: 'draft_key = ?', whereArgs: [e.draftKey]);
      await tx.delete('drafts', where: 'key = ?', whereArgs: [e.draftKey]);
      await tx.insert('notices', {'message': message, 'created_at': DateTime.now().toUtc().toIso8601String()});
    });
  }

  /// After a fresh snapshot, drafts with nothing left to send are already reflected in it.
  Future<void> pruneDrafts() =>
      db.rawDelete('DELETE FROM drafts WHERE key NOT IN (SELECT DISTINCT draft_key FROM outbox)');

  Future<List<Notice>> notices() async => (await db.query('notices', orderBy: 'id DESC'))
      .map((r) => Notice(id: r['id'] as int, message: r['message'] as String, createdAt: DateTime.parse(r['created_at'] as String)))
      .toList();

  Future<void> dismissNotice(int id) => db.delete('notices', where: 'id = ?', whereArgs: [id]);

  Future<void> addNotice(String message) =>
      db.insert('notices', {'message': message, 'created_at': DateTime.now().toUtc().toIso8601String()});

  // ---- Inspections ----

  Future<void> saveInspection(LocalInspection i) => db.insert('inspections', i.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<LocalInspection>> inspections({String? status}) async =>
      (await db.query('inspections', where: status == null ? null : 'status = ?', whereArgs: status == null ? null : [status], orderBy: 'updated_at DESC'))
          .map(LocalInspection.fromRow)
          .toList();

  Future<LocalInspection?> inspection(String clientId) async {
    final r = await db.query('inspections', where: 'client_id = ?', whereArgs: [clientId]);
    return r.isEmpty ? null : LocalInspection.fromRow(r.first);
  }

  Future<void> deleteInspection(String clientId) async {
    await db.transaction((tx) async {
      await tx.delete('inspection_photos', where: 'inspection_id = ?', whereArgs: [clientId]);
      await tx.delete('inspections', where: 'client_id = ?', whereArgs: [clientId]);
    });
  }

  Future<void> savePhoto(LocalPhoto p) => db.insert('inspection_photos', p.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deletePhoto(String clientId) => db.delete('inspection_photos', where: 'client_id = ?', whereArgs: [clientId]);

  Future<List<LocalPhoto>> photos({String? inspectionId, String? status}) async {
    final where = <String>[], args = <Object>[];
    if (inspectionId != null) {
      where.add('inspection_id = ?');
      args.add(inspectionId);
    }
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    return (await db.query('inspection_photos', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy: 'created_at'))
        .map(LocalPhoto.fromRow)
        .toList();
  }

  /// Inspections and photos waiting to be sent.
  Future<int> inspectionsWaiting() async =>
      (utils.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM inspections WHERE status = 'queued'")) ?? 0) +
      (utils.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM inspection_photos WHERE status = 'queued'")) ?? 0);

  Future<void> wipe() async {
    for (final t in ['meta', 'outbox', 'drafts', 'notices', 'inspections', 'inspection_photos']) {
      await db.delete(t);
    }
  }
}

/// An inspection on this phone. [answers] maps section key to item key to the answer.
class LocalInspection {
  LocalInspection({
    required this.clientId,
    required this.schoolId,
    required this.schoolName,
    required this.visitedOn,
    required this.answers,
    this.notes,
    this.status = 'draft',
    this.serverId,
    this.overall,
    this.error,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();
  final String clientId;
  final String schoolId;
  final String schoolName;
  String visitedOn;
  final Map<String, Map<String, Object?>> answers;
  String? notes;
  /// draft, queued (submitted, waiting to send), sent or failed.
  String status;
  String? serverId;
  String? overall;
  String? error;
  DateTime updatedAt;

  Map<String, Object?> toRow() => {
        'client_id': clientId,
        'school_id': schoolId,
        'school_name': schoolName,
        'visited_on': visitedOn,
        'answers': jsonEncode(answers),
        'notes': notes,
        'status': status,
        'server_id': serverId,
        'overall': overall,
        'error': error,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static LocalInspection fromRow(Map<String, Object?> r) => LocalInspection(
        clientId: r['client_id'] as String,
        schoolId: r['school_id'] as String,
        schoolName: r['school_name'] as String,
        visitedOn: r['visited_on'] as String,
        answers: (jsonDecode(r['answers'] as String) as Map<String, dynamic>).map((k, v) => MapEntry(k, Map<String, Object?>.from(v as Map))),
        notes: r['notes'] as String?,
        status: r['status'] as String,
        serverId: r['server_id'] as String?,
        overall: r['overall'] as String?,
        error: r['error'] as String?,
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );
}

class LocalPhoto {
  LocalPhoto({required this.clientId, required this.inspectionId, required this.section, required this.path, this.caption, this.status = 'queued', this.error, DateTime? createdAt})
      : createdAt = createdAt ?? DateTime.now();
  final String clientId;
  final String inspectionId;
  final String section;
  final String path;
  String? caption;
  /// queued, sent or failed.
  String status;
  String? error;
  final DateTime createdAt;

  Map<String, Object?> toRow() => {
        'client_id': clientId,
        'inspection_id': inspectionId,
        'section': section,
        'caption': caption,
        'path': path,
        'status': status,
        'error': error,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static LocalPhoto fromRow(Map<String, Object?> r) => LocalPhoto(
        clientId: r['client_id'] as String,
        inspectionId: r['inspection_id'] as String,
        section: r['section'] as String,
        caption: r['caption'] as String?,
        path: r['path'] as String,
        status: r['status'] as String,
        error: r['error'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}
