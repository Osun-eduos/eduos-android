// Sends queued changes in order, then downloads a fresh snapshot.
import '../net/api.dart';
import '../store/local_store.dart';

enum SyncOutcome { synced, offline, signedOut, failed }

class SyncReport {
  SyncReport(this.outcome, {this.applied = 0, this.rejected = 0, this.waiting = 0, this.message});
  final SyncOutcome outcome;
  final int applied;
  final int rejected;
  final int waiting;
  final String? message;
}

class SyncEngine {
  SyncEngine({required this.api, required this.store, required this.deviceId, this.batchSize = 50});
  final Api api;
  final LocalStore store;
  final String deviceId;
  final int batchSize;
  Future<SyncReport>? _running;

  /// Runs one sync. Calls made while one is running share its result.
  Future<SyncReport> run() => _running ??= _run().whenComplete(() => _running = null);

  /// Calls [fn]; on an expired access token refreshes once and tries again.
  Future<T> _authed<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      if (!await api.refresh()) throw _SignedOut();
      return await fn();
    }
  }

  Future<SyncReport> _run() async {
    var applied = 0, rejected = 0;
    try {
      // 1. Upload queued changes, oldest first.
      while (true) {
        final batch = await store.pending(limit: batchSize);
        if (batch.isEmpty) break;
        final results = await _authed(() => api.push(deviceId, batch.map((e) => e.toWire()).toList()));
        final byId = {for (final r in results) r['id'] as String: r};
        var stop = false;
        for (final e in batch) {
          final r = byId[e.id];
          final status = r?['status'];
          if (status == 'applied') {
            await store.removeEvent(e.id);
            applied++;
          } else if (status == 'rejected') {
            await store.reject(e, describe(e, r?['message'] as String? ?? 'The change was not accepted.'));
            rejected++;
          } else {
            await store.markAttempt(e.id, r?['message'] as String? ?? 'Not sent yet.');
            stop = true;
            break;
          }
        }
        if (stop) {
          return SyncReport(SyncOutcome.offline, applied: applied, rejected: rejected, waiting: await store.pendingCount(),
              message: 'The EduOS service is busy. Your changes are saved and will be sent later.');
        }
      }
      // 2. Download the latest working set, then drop drafts it now reflects.
      final snap = await _authed(() => api.snapshot());
      await store.saveSnapshot(snap, DateTime.now());
      await store.pruneDrafts();
      return SyncReport(SyncOutcome.synced, applied: applied, rejected: rejected);
    } on _SignedOut {
      return SyncReport(SyncOutcome.signedOut, applied: applied, rejected: rejected, waiting: await store.pendingCount(),
          message: 'Please sign in again. Your unsent changes are kept.');
    } on ApiException catch (e) {
      return SyncReport(e.offline ? SyncOutcome.offline : SyncOutcome.failed,
          applied: applied, rejected: rejected, waiting: await store.pendingCount(), message: e.message);
    }
  }

  /// A plain-language notice for a refused change.
  static String describe(OutboxEvent e, String reason) {
    return '${e.label} was not accepted: $reason';
  }
}

class _SignedOut implements Exception {}
