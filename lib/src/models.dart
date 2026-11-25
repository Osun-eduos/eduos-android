// Data the app keeps offline, as sent by eduos-sync (GET /v1/snapshot).

class Student {
  Student({required this.id, required this.learnerId, required this.fullName, required this.sex, required this.admittedOn});
  final String id;
  final String learnerId;
  final String fullName;
  final String sex;
  final String admittedOn; // YYYY-MM-DD at the current school

  factory Student.fromJson(Map<String, dynamic> j) =>
      Student(id: j['id'], learnerId: j['learnerId'], fullName: j['fullName'], sex: j['sex'], admittedOn: j['admittedOn']);
}

class Mark {
  Mark({required this.studentId, required this.status, this.note});
  final String studentId;
  final String status; // PRESENT, LATE, ABSENT, EXCUSED
  final String? note;

  factory Mark.fromJson(Map<String, dynamic> j) => Mark(studentId: j['studentId'], status: j['status'], note: j['note']);
  Map<String, dynamic> toJson() => {'studentId': studentId, 'status': status, if (note != null && note!.isNotEmpty) 'note': note};
}

class Register {
  Register({required this.date, required this.marks});
  final String date;
  final List<Mark> marks;
  factory Register.fromJson(Map<String, dynamic> j) =>
      Register(date: j['date'], marks: (j['marks'] as List).map((m) => Mark.fromJson(m)).toList());
}

class SchoolClass {
  SchoolClass({required this.id, required this.name, required this.level, required this.students, required this.registers});
  final String id;
  final String name;
  final String level;
  final List<Student> students;
  final List<Register> registers;
  factory SchoolClass.fromJson(Map<String, dynamic> j) => SchoolClass(
        id: j['id'],
        name: j['name'],
        level: j['level'],
        students: (j['students'] as List).map((s) => Student.fromJson(s)).toList(),
        registers: (j['registers'] as List).map((r) => Register.fromJson(r)).toList(),
      );
}

class Component {
  Component({required this.key, required this.label, required this.max});
  final String key;
  final String label;
  final int max;
  factory Component.fromJson(Map<String, dynamic> j) => Component(key: j['key'], label: j['label'], max: (j['max'] as num).toInt());
}

typedef Marks = Map<String, double?>;

Marks marksFromJson(Object? raw) {
  if (raw is! Map) return {};
  return raw.map((k, v) => MapEntry(k as String, v == null ? null : (v as num).toDouble()));
}

class Score {
  Score({required this.studentId, required this.marks, this.total});
  final String studentId;
  final Marks marks;
  final double? total;
  factory Score.fromJson(Map<String, dynamic> j) =>
      Score(studentId: j['studentId'], marks: marksFromJson(j['marks']), total: (j['total'] as num?)?.toDouble());
}

class Sheet {
  Sheet({required this.id, required this.status, this.returnNote, required this.scores});
  final String id;
  final String status; // DRAFT, SUBMITTED, APPROVED, RETURNED
  final String? returnNote;
  final List<Score> scores;
  factory Sheet.fromJson(Map<String, dynamic> j) => Sheet(
        id: j['id'],
        status: j['status'],
        returnNote: j['returnNote'],
        scores: (j['scores'] as List).map((s) => Score.fromJson(s)).toList(),
      );
}

class Subject {
  Subject({
    required this.classSubjectId,
    required this.code,
    required this.name,
    required this.classId,
    required this.className,
    required this.level,
    required this.released,
    required this.students,
    this.sheet,
  });
  final String classSubjectId;
  final String code;
  final String name;
  final String classId;
  final String className;
  final String level;
  final bool released;
  final List<Student> students;
  final Sheet? sheet;
  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        classSubjectId: j['classSubjectId'],
        code: j['code'],
        name: j['name'],
        classId: j['classId'],
        className: j['className'],
        level: j['level'],
        released: j['released'] == true,
        students: (j['students'] as List).map((s) => Student.fromJson(s)).toList(),
        sheet: j['sheet'] == null ? null : Sheet.fromJson(j['sheet']),
      );
}

class Period {
  Period({required this.id, required this.name, required this.startDate, required this.endDate});
  final String id;
  final String name;
  final String startDate;
  final String endDate;
  factory Period.fromJson(Map<String, dynamic> j) => Period(id: j['id'], name: j['name'], startDate: j['startDate'], endDate: j['endDate']);
}

/// A state-wide holiday or other non-school day set by the Ministry. Registers are not taken on these days.
class Holiday {
  Holiday({required this.name, required this.startDate, required this.endDate});
  final String name;
  final String startDate;
  final String endDate;
  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(name: j['name'], startDate: j['startDate'], endDate: j['endDate'] ?? j['startDate']);
  bool covers(String date) => startDate.compareTo(date) <= 0 && endDate.compareTo(date) >= 0;
}

class Term extends Period {
  Term({required super.id, required super.name, required super.startDate, required super.endDate, required this.components, required this.sssGrading});
  final List<Component> components;
  final String sssGrading; // WAEC or BASIC
  factory Term.fromJson(Map<String, dynamic> j) => Term(
        id: j['id'],
        name: j['name'],
        startDate: j['startDate'],
        endDate: j['endDate'],
        components: (j['components'] as List).map((c) => Component.fromJson(c)).toList(),
        sssGrading: j['sssGrading'] ?? 'WAEC',
      );
}

class Band {
  Band({required this.min, required this.grade, required this.remark});
  final double min;
  final String grade;
  final String remark;
  factory Band.fromJson(Map<String, dynamic> j) => Band(min: (j['min'] as num).toDouble(), grade: j['grade'], remark: j['remark']);
}

/// The whole offline working set, plus the state-wide grading scales and attendance rules.
class Snapshot {
  Snapshot({
    required this.userName,
    required this.schoolName,
    required this.session,
    required this.term,
    required this.classes,
    required this.subjects,
    required this.basicScale,
    required this.sssScale,
    required this.teacherEditDays,
    required this.generatedAt,
    this.holidays = const [],
  });
  final String userName;
  final String? schoolName;
  final Period? session;
  final Term? term;
  final List<SchoolClass> classes;
  final List<Subject> subjects;
  final List<Band> basicScale;
  final List<Band> sssScale;
  final int teacherEditDays;
  final DateTime generatedAt;
  final List<Holiday> holidays;

  factory Snapshot.fromJson(Map<String, dynamic> body) {
    final s = body['snapshot'] as Map<String, dynamic>;
    final grading = (body['grading'] as Map<String, dynamic>?) ?? {};
    final scales = (grading['scales'] as Map<String, dynamic>?) ?? {};
    List<Band> scale(String k) => ((scales[k] as List?) ?? []).map((b) => Band.fromJson(b)).toList();
    return Snapshot(
      userName: s['user']['fullName'],
      schoolName: s['school']?['name'],
      session: s['session'] == null ? null : Period.fromJson(s['session']),
      term: s['term'] == null ? null : Term.fromJson(s['term']),
      classes: (s['classes'] as List).map((c) => SchoolClass.fromJson(c)).toList(),
      subjects: (s['subjects'] as List).map((c) => Subject.fromJson(c)).toList(),
      basicScale: scale('BASIC'),
      sssScale: scale('SSS'),
      teacherEditDays: ((body['attendance'] as Map?)?['teacherEditDays'] as num?)?.toInt() ?? 7,
      generatedAt: DateTime.tryParse(s['generatedAt'] ?? '') ?? DateTime.now(),
      holidays: ((s['holidays'] as List?) ?? []).map((h) => Holiday.fromJson(h)).toList(),
    );
  }
}
