// School rules the app checks offline, mirroring eduos-api. The server checks them again when changes sync.
import 'models.dart';

const statuses = ['PRESENT', 'LATE', 'ABSENT', 'EXCUSED'];
const statusLabel = {'PRESENT': 'Present', 'LATE': 'Late', 'ABSENT': 'Absent', 'EXCUSED': 'Excused'};
const statusShort = {'PRESENT': 'P', 'LATE': 'L', 'ABSENT': 'A', 'EXCUSED': 'E'};

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDate(String s) => DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));

/// Today's date in Nigeria (West Africa Time, UTC+1).
String todayNG([DateTime? now]) => isoDate((now ?? DateTime.now()).toUtc().add(const Duration(hours: 1)));

bool isWeekend(DateTime d) => d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

/// The holiday on a date, if any.
Holiday? holidayOn(List<Holiday> holidays, String date) => holidays.where((h) => h.covers(date)).firstOrNull;

/// School days a class teacher can take or correct a register for: weekdays in the session that are not
/// holidays, from [editDays] days ago up to today. Newest first.
List<String> registerDates({required String today, required Period session, required int editDays, List<Holiday> holidays = const []}) {
  final t = parseDate(today);
  final start = parseDate(session.startDate);
  final end = parseDate(session.endDate);
  final from = t.subtract(Duration(days: editDays));
  final out = <String>[];
  for (var d = t; !d.isBefore(from); d = d.subtract(const Duration(days: 1))) {
    if (isWeekend(d) || d.isBefore(start) || d.isAfter(end)) continue;
    final iso = isoDate(d);
    if (holidayOn(holidays, iso) != null) continue;
    out.add(iso);
  }
  return out;
}

/// Students on the roll on a given day (admitted to the school by then).
List<Student> rollOn(List<Student> students, String date) => students.where((s) => s.admittedOn.compareTo(date) <= 0).toList();

/// Students on the roll during a term (admitted by its last day).
List<Student> rollForTerm(List<Student> students, Term term) => rollOn(students, term.endDate);

/// A problem with one mark as typed, or null if it is fine. Empty means not entered yet.
String? markProblem(String text, Component c) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final n = double.tryParse(t);
  if (n == null || n < 0 || n > c.max) return '0 to ${c.max}';
  if ((n * 2).roundToDouble() != n * 2) return 'Whole or half marks';
  return null;
}

/// Total when every component has a mark, otherwise null.
double? totalOf(Marks marks, List<Component> components) {
  var sum = 0.0;
  for (final c in components) {
    final v = marks[c.key];
    if (v == null) return null;
    sum += v;
  }
  return (sum * 10).roundToDouble() / 10;
}

/// Senior secondary uses the term's choice (WAEC A1 to F9, or A to F); everyone else uses A to F.
List<Band> scaleFor(String level, Term term, Snapshot snap) =>
    level.startsWith('SSS') && term.sssGrading == 'WAEC' ? snap.sssScale : snap.basicScale;

Band? gradeFor(double? total, List<Band> scale) {
  if (total == null) return null;
  for (final b in scale) {
    if (total >= b.min) return b;
  }
  return null;
}

String formatMark(double? v) {
  if (v == null) return '';
  return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
