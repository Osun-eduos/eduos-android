// Screens for parents: each child at a glance, their attendance and report cards, and the notification inbox.
// Everything shown is kept on the phone, so it opens without a connection.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../parent.dart';
import '../rules.dart';
import 'home_screen.dart' show SyncCard;
import 'theme.dart';

String _pct(double? v) => v == null ? '–' : '${v % 1 == 0 ? v.toInt() : v}%';
String _day(String iso) => DateFormat('EEE d MMM').format(parseDate(iso));
const _statusText = {'PRESENT': 'Present', 'LATE': 'Late', 'ABSENT': 'Absent', 'EXCUSED': 'Excused'};
const _kindIcon = {'ABSENCE': Icons.event_busy, 'RESULTS': Icons.school, 'TRANSFER': Icons.swap_horiz, 'NOTICE': Icons.campaign};

class ParentHomeScreen extends StatelessWidget {
  const ParentHomeScreen({super.key});

  Future<void> _signOut(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text("Your children's details are removed from this phone until you sign in again."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out', style: TextStyle(color: bad))),
        ],
      ),
    );
    if (ok == true) await app.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.parentData!;
    final unread = data.unread;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EduOS'),
        actions: [
          IconButton(
            key: const Key('open-inbox'),
            tooltip: unread > 0 ? '$unread unread notifications' : 'Notifications',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxScreen())),
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'out' ? _signOut(context, app) : app.sync(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'sync', child: Text('Sync now')), PopupMenuItem(value: 'out', child: Text('Sign out'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: app.sync,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Good day, ${(app.userName ?? data.userName).split(' ').first}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const SyncCard(),
            if (unread > 0)
              Card(
                color: indigo.withValues(alpha: 0.06),
                child: ListTile(
                  leading: const Icon(Icons.notifications_active, color: indigo),
                  title: Text('$unread new notification${unread == 1 ? '' : 's'}'),
                  subtitle: Text(data.inbox.firstWhere((n) => !n.read).title),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InboxScreen())),
                ),
              ),
            const SizedBox(height: 8),
            if (data.children.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No children are linked to your account yet. Ask the school to link them.'))),
            for (final c in data.children) _ChildCard(child: c),
          ],
        ),
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child});
  final Child child;
  @override
  Widget build(BuildContext context) {
    final c = child;
    final card = c.latestCard;
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChildScreen(childId: c.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.fullName, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text([c.className, c.schoolName].whereType<String>().join(' · ')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Figure(label: 'Attendance', value: _pct(c.attendance.rate), note: c.attendance.absences > 0 ? '${c.attendance.absences} absent' : null)),
              Expanded(child: _Figure(label: card == null ? 'Report card' : card.termName, value: card == null ? 'None yet' : _pct(card.average), note: card?.position != null ? '${card!.position} of ${card.outOf}' : null)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.note});
  final String label;
  final String value;
  final String? note;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: t.labelSmall),
      Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      if (note != null) Text(note!, style: t.bodySmall),
    ]);
  }
}

class ChildScreen extends StatelessWidget {
  const ChildScreen({super.key, required this.childId, this.termId});
  final String childId;
  final String? termId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = app.child(childId);
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This child is no longer linked to your account.')));
    final t = Theme.of(context).textTheme;
    return DefaultTabController(
      length: 2,
      initialIndex: termId != null ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.firstName),
          bottom: const TabBar(tabs: [Tab(text: 'Attendance'), Tab(text: 'Report cards')]),
        ),
        body: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(16), children: [
            Text(c.fullName, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text([c.className, c.schoolName, if (c.classTeacher != null) 'Class teacher: ${c.classTeacher}'].whereType<String>().join(' · ')),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(child: _Figure(label: 'This session', value: _pct(c.attendance.rate))),
                  for (final s in ['PRESENT', 'LATE', 'ABSENT', 'EXCUSED']) Expanded(child: _Figure(label: _statusText[s]!, value: '${c.attendance.counts[s] ?? 0}')),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            if (c.attendance.records.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No registers yet this session.')),
            for (final r in c.attendance.records.take(60))
              ListTile(
                dense: true,
                title: Text(_day(r.date)),
                subtitle: r.note == null ? null : Text(r.note!),
                trailing: Pill(_statusText[r.status] ?? r.status, color: statusColor(r.status)),
              ),
          ]),
          _ReportCards(child: c, initialTerm: termId),
        ]),
      ),
    );
  }
}

class _ReportCards extends StatefulWidget {
  const _ReportCards({required this.child, this.initialTerm});
  final Child child;
  final String? initialTerm;
  @override
  State<_ReportCards> createState() => _ReportCardsState();
}

class _ReportCardsState extends State<_ReportCards> {
  String? _termId;
  ReportCard? _card;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final terms = widget.child.terms;
    _termId = widget.initialTerm ?? (terms.isEmpty ? null : terms.first.$1);
    _load();
  }

  Future<void> _load() async {
    if (_termId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final card = await context.read<AppState>().reportCard(widget.child.id, _termId!);
      if (mounted) setState(() => _card = card);
    } catch (_) {
      if (mounted) setState(() => _error = 'This report card needs a connection to open. Try again when you are online.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final terms = widget.child.terms;
    final t = Theme.of(context).textTheme;
    if (terms.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No report cards yet. You will be notified when the school releases one.', textAlign: TextAlign.center)));
    final c = _card;
    return ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<String>(
        initialValue: terms.any((x) => x.$1 == _termId) ? _termId : terms.first.$1,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Term'),
        items: [for (final (id, name) in terms) DropdownMenuItem(value: id, child: Text(name, overflow: TextOverflow.ellipsis))],
        onChanged: (v) {
          _termId = v;
          _load();
        },
      ),
      const SizedBox(height: 12),
      if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      if (_error != null && !_loading) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_error!))),
      if (c != null && !_loading && _error == null) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: _Figure(label: 'Average', value: _pct(c.average))),
              Expanded(child: _Figure(label: 'Position', value: c.position ?? '–', note: c.outOf != null && c.position != null ? 'of ${c.outOf}' : null)),
              Expanded(child: _Figure(label: 'Attendance', value: _pct(c.attendanceRate))),
            ]),
          ),
        ),
        Card(
          child: Column(children: [
            for (final s in c.subjects)
              ListTile(
                dense: true,
                title: Text(s.name),
                subtitle: s.remark == null ? null : Text(s.remark!),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.total == null ? '–' : '${s.total! % 1 == 0 ? s.total!.toInt() : s.total}', style: t.titleMedium),
                  const SizedBox(width: 10),
                  SizedBox(width: 34, child: Text(s.grade ?? '', textAlign: TextAlign.center, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                ]),
              ),
          ]),
        ),
        if (c.teacherRemark != null || c.principalRemark != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (c.teacherRemark != null) ...[Text('Class teacher', style: t.labelMedium), Text(c.teacherRemark!), const SizedBox(height: 8)],
                if (c.principalRemark != null) ...[Text('Principal', style: t.labelMedium), Text(c.principalRemark!)],
              ]),
            ),
          ),
        if (c.nextTermBegins != null) Padding(padding: const EdgeInsets.all(8), child: Text('Next term begins ${_day(c.nextTermBegins!)}.')),
      ],
    ]);
  }
}

class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.parentData?.inbox ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [if (items.any((n) => !n.read)) TextButton(onPressed: () => app.markRead(items.map((n) => n.id)), child: const Text('Mark all read'))],
      ),
      body: items.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Nothing yet. Absences, report cards and school notices appear here.', textAlign: TextAlign.center)))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, n) {
                final i = items[n];
                return ListTile(
                  leading: Icon(_kindIcon[i.kind] ?? Icons.notifications, color: i.read ? Colors.grey : indigo),
                  title: Text(i.title, style: TextStyle(fontWeight: i.read ? FontWeight.w400 : FontWeight.w700)),
                  subtitle: Text('${i.body}\n${DateFormat('EEE d MMM, h:mm a').format(i.at.toLocal())}'),
                  isThreeLine: true,
                  onTap: () {
                    app.markRead([i.id]);
                    final child = i.childId;
                    if (child != null && app.child(child) != null) {
                      final term = RegExp(r'term=([0-9a-f-]{36})').firstMatch(i.link ?? '')?.group(1);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ChildScreen(childId: child, termId: term)));
                    }
                  },
                );
              },
            ),
    );
  }
}
