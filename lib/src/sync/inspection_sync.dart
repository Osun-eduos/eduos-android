// Sync for inspectors and LGA officers. Their phones talk to eduos-api directly: submitted inspections go first,
// then their photos one at a time, then the schools, checklist and recent visits are refreshed for offline use.
// Every upload carries an id made on the phone, so sending it twice (after a dropped connection) saves it once.
import 'dart:convert';
import 'dart:io';

import '../net/api.dart';
import '../store/local_store.dart';
import 'sync_engine.dart';

class InspectionSync {
  InspectionSync({required this.api, required this.store, required this.userName, this.lga});
  final Api api;
  final LocalStore store;
  final String userName;
  final String? lga;
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

  /// A refusal the API will give again if asked again (bad data, no access), as opposed to an outage.
  static bool _final(ApiException e) => e.status >= 400 && e.status < 500 && e.status != 401 && e.status != 408 && e.status != 429;

  Future<SyncReport> _run() async {
    var applied = 0, rejected = 0;
    try {
      for (final i in await store.inspections(status: 'queued')) {
        try {
          final r = await _authed(() => api.apiPost('/inspections', {
                'clientId': i.clientId,
                'schoolId': i.schoolId,
                'visitedOn': i.visitedOn,
                'answers': i.answers,
                if (i.notes != null && i.notes!.trim().isNotEmpty) 'notes': i.notes!.trim(),
                if (i.actionNeeded != null && i.actionNeeded!.trim().isNotEmpty) 'actionNeeded': i.actionNeeded!.trim(),
              }));
          i
            ..status = 'sent'
            ..serverId = r['id'] as String
            ..overall = r['overall'] as String?
            ..error = null;
          await store.saveInspection(i);
          applied++;
        } on ApiException catch (e) {
          if (!_final(e)) rethrow;
          i
            ..status = 'failed'
            ..error = e.message;
          await store.saveInspection(i);
          await store.addNotice('The inspection of ${i.schoolName} was not accepted: ${e.message}');
          rejected++;
        }
      }
      final sent = {for (final i in await store.inspections(status: 'sent')) i.clientId: i.serverId};
      for (final p in await store.photos(status: 'queued')) {
        final serverId = sent[p.inspectionId];
        if (serverId == null) continue; // Its inspection has not reached the server yet.
        final file = File(p.path);
        if (!await file.exists()) {
          p
            ..status = 'failed'
            ..error = 'The photo file is no longer on this phone.';
          await store.savePhoto(p);
          continue;
        }
        try {
          await _authed(() => api.apiUpload('/inspections/$serverId/photos', file, {
                'clientId': p.clientId,
                'section': p.section,
                if (p.caption != null && p.caption!.trim().isNotEmpty) 'caption': p.caption!.trim(),
              }));
          p.status = 'sent';
          await store.savePhoto(p);
          // The server has it now; free the space on the phone.
          try {
            await file.delete();
          } catch (_) {}
          applied++;
        } on ApiException catch (e) {
          if (!_final(e)) rethrow;
          p
            ..status = 'failed'
            ..error = e.status == 413 ? 'The photo is too large.' : e.message;
          await store.savePhoto(p);
          rejected++;
        }
      }

      final schools = await _authed(() => api.apiGet('/schools/directory'));
      final template = await _authed(() => api.apiGet('/inspections/template'));
      final recent = await _authed(() => api.apiGet('/inspections?mine=true'));
      await store.setMeta('inspector', jsonEncode({
        'schools': schools['items'],
        'template': template,
        'recent': ((recent['items'] as List?) ?? []).take(30).toList(),
        'userName': userName,
        'lga': lga,
      }));
      await store.setMeta('lastSyncAt', DateTime.now().toUtc().toIso8601String());
      return SyncReport(SyncOutcome.synced, applied: applied, rejected: rejected);
    } on _SignedOut {
      return SyncReport(SyncOutcome.signedOut, applied: applied, rejected: rejected, waiting: await store.inspectionsWaiting(),
          message: 'Please sign in again. Your unsent inspections are kept.');
    } on ApiException catch (e) {
      return SyncReport(e.offline ? SyncOutcome.offline : SyncOutcome.failed,
          applied: applied, rejected: rejected, waiting: await store.inspectionsWaiting(),
          message: e.offline ? 'No connection. Your inspections are saved on this phone.' : e.message);
    }
  }
}

class _SignedOut implements Exception {}
