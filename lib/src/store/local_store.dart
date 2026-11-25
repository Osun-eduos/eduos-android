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
];

class LocalStore {
  LocalStore(this.db);
  final Database db;

  static Future<void> create(Database db, int version) async {
    for (final s in schema) {
      await db.execute(s);
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

  Future<void> wipe() async {
    for (final t in ['meta', 'outbox', 'drafts', 'notices']) {
      await db.delete(t);
    }
  }
}
