import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'register_screen.dart';
import 'scores_screen.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _signOut(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(app.pending > 0
            ? '${app.pending} change${app.pending == 1 ? ' has' : 's have'} not been sent yet. Signing out deletes ${app.pending == 1 ? 'it' : 'them'} from this phone. Connect to the internet and sync first.'
            : 'Your classes are removed from this phone until you sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(app.pending > 0 ? 'Delete and sign out' : 'Sign out', style: const TextStyle(color: bad))),
        ],
      ),
    );
    if (ok == true) await app.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.snapshot!;
    final today = app.today;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EduOS'),
        actions: [
          IconButton(tooltip: 'Sync now', onPressed: app.syncing ? null : app.sync, icon: const Icon(Icons.sync)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'out' ? _signOut(context, app) : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'out', child: Text('Sign out'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: app.sync,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Good day, ${s.userName.split(' ').first}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text([s.schoolName, s.term?.name ?? s.session?.name].whereType<String>().join(' · '), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            const SyncCard(),
            for (final n in app.notices)
              Card(
                color: bad.withValues(alpha: 0.06),
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: bad),
                  title: Text(n.message),
                  trailing: IconButton(tooltip: 'Dismiss', icon: const Icon(Icons.close), onPressed: () => app.dismissNotice(n.id)),
                ),
              ),
            if (s.session == null) const _Empty('The Ministry has not opened an academic session yet.'),
            if (s.classes.isNotEmpty) ...[
              const _Heading('Registers'),
              for (final c in s.classes)
                Builder(builder: (context) {
                  final r = app.registerFor(c, today);
                  final schoolDay = app.registerDays().contains(today);
                  return Card(
                    child: ListTile(
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${c.students.length} students · ${!schoolDay ? 'Not a school day' : r.taken ? (r.waiting ? "Today's register saved, waiting to sync" : "Today's register taken") : "Today's register not taken"}'),
                      trailing: Icon(r.taken ? Icons.check_circle : Icons.chevron_right, color: r.taken ? good : null),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(classId: c.id))),
                    ),
                  );
                }),
            ],
            if (s.subjects.isNotEmpty) ...[
              _Heading(s.term == null ? 'Scores' : 'Scores · ${s.term!.name}'),
              for (final sj in s.subjects)
                Builder(builder: (context) {
                  final v = app.sheetFor(sj);
                  return Card(
                    child: ListTile(
                      title: Text(sj.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${sj.className}${v.waiting ? ' · waiting to sync' : ''}'),
                      trailing: Pill(sj.released ? 'Released' : statusText[v.status]!, color: sj.released ? good : statusColor(v.status)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ScoresScreen(classSubjectId: sj.classSubjectId))),
                    ),
                  );
                }),
            ],
            if (s.session != null && s.classes.isEmpty && s.subjects.isEmpty)
              const _Empty('You have no class or subjects yet. Your school administrator assigns them on the EduOS website.'),
          ],
        ),
      ),
    );
  }
}

class SyncCard extends StatelessWidget {
  const SyncCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final when = app.lastSync == null ? 'never' : DateFormat('EEE d MMM, h:mm a').format(app.lastSync!.toLocal());
    final (icon, color, text) = app.syncing
        ? (Icons.sync, indigo, 'Syncing…')
        : app.pending > 0
            ? (Icons.cloud_off, warn, '${app.pending} change${app.pending == 1 ? '' : 's'} saved on this phone, waiting to sync${app.syncMessage != null ? '. ${app.syncMessage}' : ''}')
            : app.syncMessage != null
                ? (Icons.cloud_off, warn, app.syncMessage!)
                : (Icons.cloud_done, good, 'Everything is synced');
    return Card(
      child: ListTile(
        leading: app.syncing ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, color: color),
        title: Text(text),
        subtitle: Text('Last synced $when'),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(text)));
}
