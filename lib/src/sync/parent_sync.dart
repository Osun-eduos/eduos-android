// Sync for parents. Their phones talk to eduos-api directly: first any "read" marks made offline, then a fresh
// copy of each child's details, attendance and latest report card, and the inbox, kept on the phone.
import 'dart:convert';

import '../net/api.dart';
import '../store/local_store.dart';
import 'sync_engine.dart';

class ParentSync {
  ParentSync({required this.api, required this.store, required this.userName});
  final Api api;
  final LocalStore store;
  final String userName;
  Future<SyncReport>? _running;

  Future<SyncReport> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<T> _authed<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      if (!await api.refresh()) throw _SignedOut();
      return await fn();
    }
  }

  /// Extras (progress, exam timetable, school notices) that an older server may not have: a 404 is not a failure.
  Future<Map<String, dynamic>?> _optional(String path) async {
    try {
      return await _authed(() => api.apiGet(path));
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Notifications read on this phone while offline, waiting to be told to the server.
  static Future<Set<String>> pendingReads(LocalStore s) async => ((jsonDecode(await s.meta('pendingRead') ?? '[]') as List).cast<String>()).toSet();

  static Future<void> addPendingReads(LocalStore s, Iterable<String> ids) async =>
      s.setMeta('pendingRead', jsonEncode({...await pendingReads(s), ...ids}.toList()));

  Future<SyncReport> _run() async {
    try {
      final reads = await pendingReads(store);
      if (reads.isNotEmpty) {
        await _authed(() => api.apiPost('/notifications/read', {'ids': reads.take(200).toList()}));
        await store.setMeta('pendingRead', jsonEncode(reads.skip(200).toList()));
      }
      final kids = ((await _authed(() => api.apiGet('/my/children')))['items'] as List? ?? []).cast<Map<String, dynamic>>();
      final children = <Map<String, dynamic>>[];
      for (final k in kids) {
        final id = k['id'] as String;
        final attendance = await _authed(() => api.apiGet('/attendance/students/$id'));
        final terms = ((await _authed(() => api.apiGet('/report-cards/$id/terms')))['items'] as List? ?? []).cast<Map<String, dynamic>>();
        final released = terms.where((t) => t['released'] == true).toList();
        Map<String, dynamic>? card;
        if (released.isNotEmpty) card = await _authed(() => api.apiGet('/report-cards/$id?termId=${released.first['termId']}'));
        final progress = (await _optional('/report-cards/$id/progress'))?['items'] ?? [];
        final exams = await _optional('/exam-papers/student/$id');
        children.add({...k, 'attendance': attendance, 'terms': terms, 'latestCard': card, 'progress': progress, 'exams': exams});
      }
      final inbox = await _authed(() => api.apiGet('/notifications'));
      final notices = (await _optional('/notices/mine'))?['items'] ?? [];
      await store.setMeta('parent', jsonEncode({'userName': userName, 'children': children, 'inbox': inbox['items'] ?? [], 'notices': notices}));
      await store.setMeta('lastSyncAt', DateTime.now().toUtc().toIso8601String());
      return SyncReport(SyncOutcome.synced, applied: reads.length);
    } on _SignedOut {
      return SyncReport(SyncOutcome.signedOut, message: 'Please sign in again.');
    } on ApiException catch (e) {
      return SyncReport(e.offline ? SyncOutcome.offline : SyncOutcome.failed,
          message: e.offline ? 'No connection. Showing what was saved on this phone.' : e.message);
    }
  }

  /// One report card, fetched when the parent opens a term that is not kept on the phone.
  Future<Map<String, dynamic>> reportCard(String studentId, String termId) => _authed(() => api.apiGet('/report-cards/$studentId?termId=$termId'));
}

class _SignedOut implements Exception {}
