import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../rules.dart';
import 'theme.dart';

/// One subject's score sheet: the class list with totals and grades, a one-student-per-screen entry view,
/// save (to the phone, then sync) and submit for approval.
class ScoresScreen extends StatefulWidget {
  const ScoresScreen({super.key, required this.classSubjectId});
  final String classSubjectId;
  @override
  State<ScoresScreen> createState() => _ScoresScreenState();
}

class _ScoresScreenState extends State<ScoresScreen> {
  /// Text as typed, per student and component. Only students the teacher touched are here.
  final Map<String, Map<String, String>> _typed = {};

  Subject get _subject => context.read<AppState>().snapshot!.subjects.firstWhere((s) => s.classSubjectId == widget.classSubjectId);

  String _text(SheetView v, String studentId, Component c) => _typed[studentId]?[c.key] ?? formatMark(v.marks[studentId]?[c.key]);

  Marks _marksOf(SheetView v, String studentId, List<Component> comps) => {
        for (final c in comps) c.key: double.tryParse(_text(v, studentId, c).trim()),
      };

  bool _invalid(SheetView v, List<Component> comps) =>
      _typed.entries.any((e) => comps.any((c) => markProblem(e.value[c.key] ?? '', c) != null));

  Future<void> _save(SheetView v, List<Component> comps) async {
    if (_invalid(v, comps)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fix the marks shown in red first.')));
      return;
    }
    final changes = {for (final sid in _typed.keys) sid: _marksOf(v, sid, comps)};
    await context.read<AppState>().saveScores(_subject, changes);
    if (!mounted) return;
    setState(_typed.clear);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scores saved on this phone. They will sync when you are online.')));
  }

  Future<void> _submit(SheetView v, List<Component> comps) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Submit for approval?'),
        content: const Text('Your school administrator will review the scores. You cannot change them after submitting unless they are returned to you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_typed.isNotEmpty) await _save(v, comps);
    if (!mounted) return;
    await context.read<AppState>().submitScores(_subject);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final snap = app.snapshot!;
    final s = _subject;
    final term = snap.term;
    final v = app.sheetFor(s);
    if (term == null) {
      return Scaffold(appBar: AppBar(title: Text(s.name)), body: const Center(child: Text('The Ministry has not set the current term yet.')));
    }
    final comps = term.components;
    final roll = rollForTerm(s.students, term);
    final scale = scaleFor(s.level, term, snap);
    final totals = {for (final st in roll) st.id: totalOf(_marksOf(v, st.id, comps), comps)};
    final complete = totals.values.where((t) => t != null).length;
    final dirty = _typed.isNotEmpty;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Save your scores?'),
            content: const Text('You have marks that are not saved yet.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
              FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${s.name} · ${s.className}')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(children: [
              Pill(s.released ? 'Released' : statusText[v.status]!, color: s.released ? good : statusColor(v.status)),
              const SizedBox(width: 8),
              Expanded(child: Text('${term.name} · ${comps.map((c) => '${c.label} ${c.max}').join(' · ')}', style: Theme.of(context).textTheme.bodySmall)),
            ]),
            if (v.waiting) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Saved on this phone, waiting to sync.', style: TextStyle(color: warn))),
            if (v.returnNote != null)
              Card(color: bad.withValues(alpha: 0.06), child: Padding(padding: const EdgeInsets.all(12), child: Text('Returned: ${v.returnNote}', style: const TextStyle(color: bad)))),
            if (v.lockedReason != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(v.lockedReason!)),
            const SizedBox(height: 8),
            Text('$complete of ${roll.length} complete', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (var i = 0; i < roll.length; i++)
              Card(
                child: ListTile(
                  title: Text(roll[i].fullName),
                  subtitle: Text(comps.map((c) => '${c.label}: ${_text(v, roll[i].id, c).isEmpty ? '–' : _text(v, roll[i].id, c)}').join('   ')),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(formatMark(totals[roll[i].id]).isEmpty ? '–' : formatMark(totals[roll[i].id]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(gradeFor(totals[roll[i].id], scale)?.grade ?? '', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _EntryPager(
                          roll: roll,
                          start: i,
                          components: comps,
                          scale: scale,
                          editable: v.editable,
                          textOf: (sid, c) => _text(v, sid, c),
                          onChanged: (sid, key, text) => setState(() => (_typed[sid] ??= {})[key] = text),
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              ),
          ],
        ),
        bottomNavigationBar: !v.editable
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(onPressed: dirty ? () => _save(v, comps) : null, child: const Text('Save')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: complete == roll.length && roll.isNotEmpty && !_invalid(v, comps) ? () => _submit(v, comps) : null,
                        child: const Text('Submit for approval'),
                      ),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }
}

/// One student per page, with large number fields and the total and grade as you type.
class _EntryPager extends StatefulWidget {
  const _EntryPager({
    required this.roll,
    required this.start,
    required this.components,
    required this.scale,
    required this.editable,
    required this.textOf,
    required this.onChanged,
  });
  final List<Student> roll;
  final int start;
  final List<Component> components;
  final List<Band> scale;
  final bool editable;
  final String Function(String studentId, Component c) textOf;
  final void Function(String studentId, String key, String text) onChanged;
  @override
  State<_EntryPager> createState() => _EntryPagerState();
}

class _EntryPagerState extends State<_EntryPager> {
  late final PageController _pages = PageController(initialPage: widget.start);
  late int _index = widget.start;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Student ${_index + 1} of ${widget.roll.length}')),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.roll.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => _StudentEntry(
          key: ValueKey(widget.roll[i].id),
          student: widget.roll[i],
          components: widget.components,
          scale: widget.scale,
          editable: widget.editable,
          textOf: widget.textOf,
          onChanged: (k, t) {
            widget.onChanged(widget.roll[i].id, k, t);
            setState(() {});
          },
          onDone: () => i + 1 < widget.roll.length
              ? _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
              : Navigator.pop(context),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: _index == 0 ? null : () => _pages.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut), child: const Text('Previous'))),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _index + 1 < widget.roll.length ? _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : Navigator.pop(context),
                child: Text(_index + 1 < widget.roll.length ? 'Next' : 'Done'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _StudentEntry extends StatefulWidget {
  const _StudentEntry({super.key, required this.student, required this.components, required this.scale, required this.editable, required this.textOf, required this.onChanged, required this.onDone});
  final Student student;
  final List<Component> components;
  final List<Band> scale;
  final bool editable;
  final String Function(String studentId, Component c) textOf;
  final void Function(String key, String text) onChanged;
  final VoidCallback onDone;
  @override
  State<_StudentEntry> createState() => _StudentEntryState();
}

class _StudentEntryState extends State<_StudentEntry> {
  late final Map<String, TextEditingController> _c = {
    for (final c in widget.components) c.key: TextEditingController(text: widget.textOf(widget.student.id, c)),
  };
  late final Map<String, FocusNode> _f = {for (final c in widget.components) c.key: FocusNode()};

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    for (final x in _f.values) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marks = <String, double?>{for (final c in widget.components) c.key: markProblem(_c[c.key]!.text, c) == null ? double.tryParse(_c[c.key]!.text.trim()) : null};
    final total = totalOf(marks, widget.components);
    final band = gradeFor(total, widget.scale);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(widget.student.fullName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      Text(widget.student.learnerId, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 20),
      for (var i = 0; i < widget.components.length; i++)
        Builder(builder: (context) {
          final c = widget.components[i];
          final last = i == widget.components.length - 1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              key: Key('${widget.student.id}-${c.key}'),
              controller: _c[c.key],
              focusNode: _f[c.key],
              enabled: widget.editable,
              autofocus: i == 0 && widget.editable,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              textInputAction: last ? TextInputAction.done : TextInputAction.next,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              decoration: InputDecoration(labelText: '${c.label} (out of ${c.max})', errorText: markProblem(_c[c.key]!.text, c)),
              onChanged: (t) {
                widget.onChanged(c.key, t);
                setState(() {});
              },
              onSubmitted: (_) => last ? widget.onDone() : _f[widget.components[i + 1].key]!.requestFocus(),
            ),
          );
        }),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Text('Total', style: TextStyle(fontSize: 18)),
              const Spacer(),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(total == null ? '–' : '${formatMark(total)} / 100', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            if (band != null) Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(top: 8), child: Pill('${band.grade} · ${band.remark}', color: band.min >= 40 ? good : bad))),
          ]),
        ),
      ),
    ]);
  }
}
