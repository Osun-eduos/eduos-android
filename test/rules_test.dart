import 'package:eduos_mobile/src/models.dart';
import 'package:eduos_mobile/src/rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final snap = Snapshot.fromJson(snapshotBody());
  final comps = snap.term!.components;

  test('today is the date in Nigeria', () {
    expect(todayNG(DateTime.utc(2026, 11, 24, 23, 30)), '2026-11-25');
    expect(todayNG(DateTime.utc(2026, 11, 24, 22, 59)), '2026-11-24');
  });

  test('register days are weekdays in the session within the edit window, newest first', () {
    final days = registerDates(today: '2026-11-25', session: snap.session!, editDays: 7);
    expect(days, ['2026-11-25', '2026-11-24', '2026-11-23', '2026-11-20', '2026-11-19', '2026-11-18']);
    expect(registerDates(today: '2026-09-15', session: snap.session!, editDays: 7), ['2026-09-15', '2026-09-14']);
    expect(registerDates(today: '2026-11-29', session: snap.session!, editDays: 7).first, '2026-11-27'); // Sunday
  });

  test('students admitted later are not on earlier rolls', () {
    final students = snap.classes.first.students;
    expect(rollOn(students, '2026-11-24').map((s) => s.id), ['s1', 's2']);
    expect(rollOn(students, '2026-11-25').map((s) => s.id), ['s1', 's2', 's3']);
  });

  test('marks must be within the maximum, in whole or half marks', () {
    final ca1 = comps.first;
    expect(markProblem('', ca1), isNull);
    expect(markProblem('18', ca1), isNull);
    expect(markProblem('17.5', ca1), isNull);
    expect(markProblem('21', ca1), '0 to 20');
    expect(markProblem('-1', ca1), '0 to 20');
    expect(markProblem('10.3', ca1), 'Whole or half marks');
    expect(markProblem('abc', ca1), '0 to 20');
  });

  test('totals need every component', () {
    expect(totalOf({'CA1': 18, 'CA2': 17.5, 'EXAM': 50}, comps), 85.5);
    expect(totalOf({'CA1': 18, 'CA2': null, 'EXAM': 50}, comps), isNull);
  });

  test('grades follow the level and the term setting for senior secondary', () {
    final jss = snap.subjects.first;
    expect(gradeFor(72, scaleFor(jss.level, snap.term!, snap))!.grade, 'A');
    expect(gradeFor(39, scaleFor(jss.level, snap.term!, snap))!.grade, 'F');
    expect(gradeFor(72, scaleFor('SSS_1', snap.term!, snap))!.grade, 'B2');
    final basic = Snapshot.fromJson(snapshotBody(sssGrading: 'BASIC'));
    expect(gradeFor(72, scaleFor('SSS_1', basic.term!, basic))!.grade, 'A');
    expect(gradeFor(null, snap.basicScale), isNull);
  });

  test('marks print without trailing .0', () {
    expect(formatMark(18), '18');
    expect(formatMark(17.5), '17.5');
    expect(formatMark(null), '');
  });
}
