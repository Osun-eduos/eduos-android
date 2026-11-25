import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../rules.dart';
import 'theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.classId});
  final String classId;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late String _date;
  Map<String, String> _status = {};
  Map<String, TextEditingController> _notes = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final days = app.registerDays();
    _date = days.isNotEmpty ? days.first : app.today;
    _load();
  }

  SchoolClass get _class => context.read<AppState>().snapshot!.classes.firstWhere((c) => c.id == widget.classId);

  void _load() {
    final v = context.read<AppState>().registerFor(_class, _date);
    _status = {for (final e in v.marks.entries) e.key: e.value.status};
    _notes = {for (final s in _class.students) s.id: TextEditingController(text: v.marks[s.id]?.note ?? '')};
    _dirty = false;
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('The marks you changed on this screen will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save(List<Student> roll) async {
    final marks = [
      for (final s in roll) Mark(studentId: s.id, status: _status[s.id]!, note: _status[s.id] == 'PRESENT' ? null : _notes[s.id]!.text.trim()),
    ];
    await context.read<AppState>().saveRegister(_class, _date, marks);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Register saved on this phone. It will sync when you are online.')));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final c = _class;
    final v = app.registerFor(c, _date);
    final roll = rollOn(c.students, _date);
    final unmarked = roll.where((s) => _status[s.id] == null).length;
    final days = app.registerDays();
    final counts = {for (final st in statuses) st: roll.where((s) => _status[s.id] == st).length};
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${c.name} register')),
        body: Column(children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(d == app.today ? 'Today' : DateFormat('EEE d MMM').format(parseDate(d))),
                      selected: d == _date,
                      onSelected: (_) async {
                        if (d == _date || !await _confirmLeave()) return;
                        setState(() {
                          _date = d;
                          _load();
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
          if (!v.editable) Padding(padding: const EdgeInsets.all(12), child: Text(v.lockedReason ?? '', style: const TextStyle(color: warn))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Text(v.waiting ? 'Saved on this phone, waiting to sync' : v.onServer ? 'Register taken' : 'Not taken yet', style: Theme.of(context).textTheme.bodySmall)),
              if (v.editable)
                TextButton(
                  onPressed: unmarked == 0 ? null : () => setState(() {
                    for (final s in roll) {
                      _status.putIfAbsent(s.id, () => 'PRESENT');
                    }
                    _dirty = true;
                  }),
                  child: Text(unmarked == roll.length ? 'Mark everyone present' : 'Mark the rest present'),
                ),
            ]),
          ),
          Expanded(
            child: roll.isEmpty
                ? const Center(child: Text('No students were in this class on that day.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: roll.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = roll[i];
                      final st = _status[s.id];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(s.learnerId, style: Theme.of(context).textTheme.bodySmall),
                              ]),
                            ),
                            if (v.editable)
                              SegmentedButton<String>(
                                key: Key('mark-${s.id}'),
                                showSelectedIcon: false,
                                emptySelectionAllowed: true,
                                style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.padded),
                                segments: [for (final x in statuses) ButtonSegment(value: x, label: Text(statusShort[x]!), tooltip: statusLabel[x])],
                                selected: {?st},
                                onSelectionChanged: (sel) => setState(() {
                                  if (sel.isNotEmpty) _status[s.id] = sel.first;
                                  _dirty = true;
                                }),
                              )
                            else
                              Pill(st == null ? 'Not marked' : statusLabel[st]!, color: statusColor(st ?? '')),
                          ]),
                          if (st != null && st != 'PRESENT')
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: TextField(
                                controller: _notes[s.id],
                                enabled: v.editable,
                                maxLength: 200,
                                decoration: const InputDecoration(isDense: true, hintText: 'Reason (optional)', counterText: ''),
                                onChanged: (_) => _dirty = true,
                              ),
                            ),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
        bottomNavigationBar: !v.editable || roll.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        unmarked > 0 ? '$unmarked not marked' : statuses.map((x) => '${statusShort[x]} ${counts[x]}').join(' · '),
                        style: TextStyle(color: unmarked > 0 ? warn : null),
                      ),
                    ),
                    FilledButton(
                      key: const Key('save-register'),
                      onPressed: unmarked > 0 || (!_dirty && v.taken) ? null : () => _save(roll),
                      child: Text(v.taken ? 'Save changes' : 'Save register'),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }
}
