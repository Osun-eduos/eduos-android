// Screens for inspectors and LGA education officers: their recent visits, choosing a school, and the inspection
// checklist with photos. Everything works offline; submitted inspections are sent when there is a connection.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../inspection.dart';
import '../rules.dart';
import '../store/local_store.dart';
import 'home_screen.dart' show SyncCard;
import 'theme.dart';

/// Takes or picks a photo and returns its file path, or null if cancelled. Tests replace it.
typedef PhotoTaker = Future<String?> Function(ImageSource source);
PhotoTaker takePhoto = (source) async {
  // Resized and compressed on the phone: plenty for a report, quick to send on a weak connection.
  final x = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 70);
  return x?.path;
};

Color overallColor(String? o) => switch (o) {
      'GOOD' => good,
      'FAIR' => warn,
      'POOR' || 'CRITICAL' => bad,
      _ => Colors.grey,
    };

String _day(String iso) => DateFormat('EEE d MMM yyyy').format(parseDate(iso));

class InspectorHomeScreen extends StatelessWidget {
  const InspectorHomeScreen({super.key});

  Future<void> _signOut(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(app.pending > 0
            ? '${app.pending} inspection${app.pending == 1 ? ' or photo has' : 's or photos have'} not been sent yet. Signing out deletes them from this phone. Connect to the internet and sync first.'
            : 'Drafts and your list of schools are removed from this phone until you sign in again.'),
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
    final data = app.inspector!;
    final mine = app.localInspections.where((i) => i.status != 'sent').toList();
    final sentIds = app.localInspections.where((i) => i.status == 'sent').map((i) => i.clientId).toSet();
    return Scaffold(
      appBar: AppBar(
        title: const Text('EduOS Inspections'),
        actions: [
          IconButton(tooltip: 'Sync now', onPressed: app.syncing ? null : app.sync, icon: const Icon(Icons.sync)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'out' ? _signOut(context, app) : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'out', child: Text('Sign out'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-inspection'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SchoolPickerScreen())),
        icon: const Icon(Icons.add),
        label: const Text('New inspection'),
      ),
      body: RefreshIndicator(
        onRefresh: app.sync,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text('Good day, ${(app.userName ?? data.userName).split(' ').first}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text('${app.role == 'LGA_OFFICER' ? 'LGA education officer' : 'School inspector'} · ${data.lga != null ? '${data.lga} LGA' : 'State-wide'} · ${data.schools.length} schools'),
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
            if (mine.isNotEmpty) ...[
              const _Heading('On this phone'),
              for (final i in mine)
                Card(
                  child: ListTile(
                    title: Text(i.schoolName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${_day(i.visitedOn)} · ${switch (i.status) { 'draft' => 'Draft, not submitted', 'queued' => 'Submitted, waiting to sync', _ => 'Not accepted: ${i.error}' }}'),
                    trailing: Pill(i.status == 'draft' ? 'Draft' : i.status == 'queued' ? 'Waiting' : 'Not accepted', color: i.status == 'failed' ? bad : warn),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionScreen(clientId: i.clientId))),
                  ),
                ),
            ],
            const _Heading('Your recent inspections'),
            if (data.recent.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('None yet. Tap New inspection when you visit a school.'))),
            for (final r in data.recent)
              Card(
                child: ListTile(
                  title: Text(r.schoolName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([_day(r.visitedOn), if (r.issues.isNotEmpty) r.issues.first, '${r.photoCount} photo${r.photoCount == 1 ? '' : 's'}'].join(' · ')),
                  trailing: Pill(overallText[r.overall] ?? r.overall, color: overallColor(r.overall)),
                  onTap: sentIds.contains(r.clientId) ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => InspectionScreen(clientId: r.clientId))) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SchoolPickerScreen extends StatefulWidget {
  const SchoolPickerScreen({super.key});
  @override
  State<SchoolPickerScreen> createState() => _SchoolPickerScreenState();
}

class _SchoolPickerScreenState extends State<SchoolPickerScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final words = _q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final schools = app.inspector!.schools.where((s) => words.every((w) => '${s.name} ${s.code} ${s.lga}'.toLowerCase().contains(w))).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Which school?')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            key: const Key('school-search'),
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'School name, number or LGA'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: schools.isEmpty
              ? const Center(child: Text('No school matches.'))
              : ListView.builder(
                  itemCount: schools.length,
                  itemBuilder: (context, n) {
                    final s = schools[n];
                    return ListTile(
                      title: Text(s.name),
                      subtitle: Text('${s.code} · ${s.lga}'),
                      onTap: () async {
                        final id = await app.startInspection(s);
                        if (context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => InspectionScreen(clientId: id)));
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class InspectionScreen extends StatefulWidget {
  const InspectionScreen({super.key, required this.clientId});
  final String clientId;
  @override
  State<InspectionScreen> createState() => _InspectionScreenState();
}

class _InspectionScreenState extends State<InspectionScreen> {
  late final AppState _app = context.read<AppState>();
  LocalInspection? _i;
  List<LocalPhoto> _photos = [];
  Timer? _save;
  final _notes = TextEditingController();
  final _counts = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = _app;
    final i = await app.store.inspection(widget.clientId);
    final photos = await app.photosFor(widget.clientId);
    if (!mounted) return;
    setState(() {
      _i = i;
      _photos = photos;
      _notes.text = i?.notes ?? '';
    });
  }

  @override
  void dispose() {
    _save?.cancel();
    if (_i != null && _i!.status == 'draft') _app.saveInspection(_i!);
    _notes.dispose();
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _editable => _i?.status == 'draft';

  /// Saves shortly after the last change, so typing is not slowed down.
  void _changed() {
    setState(() {});
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () => _app.saveInspection(_i!));
  }

  void _answer(String section, String item, Object? value) {
    (_i!.answers[section] ??= {})[item] = value;
    _changed();
  }

  Future<void> _addPhoto(String section) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from the gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    String? path;
    try {
      path = await takePhoto(source);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the camera. Allow camera access in the phone settings.')));
      return;
    }
    if (path == null || !mounted) return;
    final app = _app;
    await app.addPhoto(widget.clientId, section, path);
    final photos = await app.photosFor(widget.clientId);
    if (mounted) setState(() => _photos = photos);
  }

  Future<void> _submit() async {
    final app = _app;
    _save?.cancel();
    _i!.notes = _notes.text;
    await app.saveInspection(_i!);
    await app.submitInspection(widget.clientId);
    _i!.status = 'queued';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inspection submitted. It will be sent when there is a connection.')));
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text('The answers and photos are removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: bad))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _save?.cancel();
    final app = _app;
    final nav = Navigator.of(context);
    _i = null;
    await app.deleteInspection(widget.clientId);
    nav.pop();
  }

  Widget _item(ChecklistSection s, ChecklistItem it, List<(String, String)> ratings) {
    final v = _i!.answers[s.key]?[it.key];
    final title = Text(it.label, style: const TextStyle(fontWeight: FontWeight.w600));
    Widget control;
    switch (it.type) {
      case 'count':
        final c = _counts.putIfAbsent('${s.key}.${it.key}', () => TextEditingController(text: v?.toString() ?? ''));
        control = SizedBox(
          width: 110,
          child: TextField(
            key: Key('count-${s.key}-${it.key}'),
            controller: c,
            enabled: _editable,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true, hintText: '0'),
            onChanged: (t) => _answer(s.key, it.key, int.tryParse(t.trim())),
          ),
        );
      case 'yesno':
        control = SegmentedButton<bool>(
          key: Key('yesno-${s.key}-${it.key}'),
          segments: const [ButtonSegment(value: true, label: Text('Yes')), ButtonSegment(value: false, label: Text('No'))],
          selected: v is bool ? {v} : {},
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          onSelectionChanged: _editable ? (x) => _answer(s.key, it.key, x.isEmpty ? null : x.first) : null,
        );
      default:
        final options = it.type == 'rating' ? ratings : it.options;
        control = Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (value, label) in options)
              ChoiceChip(
                key: Key('choice-${s.key}-${it.key}-$value'),
                label: Text(label),
                selected: v == value,
                onSelected: _editable ? (on) => _answer(s.key, it.key, on ? value : null) : null,
              ),
          ],
        );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: it.type == 'count'
          ? Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, if (it.hint != null) Text(it.hint!, style: Theme.of(context).textTheme.bodySmall)])), control])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 6), control]),
    );
  }

  Widget _photoStrip(String section) {
    final photos = _photos.where((p) => p.section == section).toList();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final p in photos)
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: p.status == 'sent'
                ? Container(width: 84, height: 64, color: good.withValues(alpha: 0.1), child: const Icon(Icons.cloud_done, color: good))
                : Image.file(File(p.path), width: 84, height: 64, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: 84, height: 64, color: Colors.black12, child: const Icon(Icons.broken_image))),
          ),
          if (p.status != 'sent')
            Positioned(
              right: 0,
              top: 0,
              child: InkWell(
                onTap: () async {
                  final app = _app;
                  await app.removePhoto(p);
                  final photos = await app.photosFor(widget.clientId);
                  if (mounted) setState(() => _photos = photos);
                },
                child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, size: 18, color: Colors.white)),
              ),
            ),
        ]),
      if (_i!.status != 'failed' && photos.length < 6)
        OutlinedButton.icon(key: Key('photo-$section'), onPressed: () => _addPhoto(section), icon: const Icon(Icons.add_a_photo), label: const Text('Photo')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final i = _i;
    if (i == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final checklist = app.inspector!.checklist;
    final problems = checklist.problems(i.answers);
    final status = switch (i.status) {
      'draft' => null,
      'queued' => 'Submitted. Waiting to be sent; you can still add photos.',
      'sent' => 'Sent${i.overall != null ? ' · overall ${overallText[i.overall]!.toLowerCase()}' : ''}. Photos you add are sent too.',
      _ => 'Not accepted: ${i.error}',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(i.schoolName, overflow: TextOverflow.ellipsis),
        actions: [if (_editable) IconButton(tooltip: 'Delete draft', icon: const Icon(Icons.delete_outline), onPressed: _delete)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          if (status != null) Card(color: (i.status == 'failed' ? bad : good).withValues(alpha: 0.08), child: Padding(padding: const EdgeInsets.all(12), child: Text(status))),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('Visited ${_day(i.visitedOn)}'),
            trailing: _editable
                ? TextButton(
                    onPressed: () async {
                      final now = parseDate(app.today);
                      final d = await showDatePicker(context: context, initialDate: parseDate(i.visitedOn), firstDate: now.subtract(const Duration(days: 60)), lastDate: now);
                      if (d != null) {
                        i.visitedOn = isoDate(d);
                        _changed();
                      }
                    },
                    child: const Text('Change'))
                : null,
          ),
          for (final s in checklist.sections)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  for (final it in s.items) _item(s, it, checklist.ratings),
                  const SizedBox(height: 6),
                  _photoStrip(s.key),
                ]),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Notes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('inspection-notes'),
                  controller: _notes,
                  enabled: _editable,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: const InputDecoration(hintText: 'Anything else the Ministry should know'),
                  onChanged: (t) {
                    i.notes = t;
                    _changed();
                  },
                ),
                const SizedBox(height: 6),
                _photoStrip('general'),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _editable
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (problems.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(problems.first, style: const TextStyle(color: warn))),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('submit-inspection'),
                      onPressed: problems.isEmpty ? _submit : null,
                      child: const Text('Submit inspection'),
                    ),
                  ),
                ]),
              ),
            )
          : null,
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
