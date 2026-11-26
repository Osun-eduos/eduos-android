// What a parent sees: their children, each child's attendance and latest report card, and their inbox.
// Kept on the phone (in the encrypted database) so it opens without a connection.

class ChildAttendance {
  ChildAttendance({required this.rate, required this.counts, required this.records});
  final double? rate;
  final Map<String, int> counts;
  /// Newest first: date, status, note.
  final List<({String date, String status, String? note})> records;

  factory ChildAttendance.fromJson(Map<String, dynamic>? j) {
    if (j == null) return ChildAttendance(rate: null, counts: {}, records: []);
    final recs = ((j['records'] as List?) ?? [])
        .map((r) => (date: r['date'] as String, status: r['status'] as String, note: r['note'] as String?))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return ChildAttendance(
      rate: (j['rate'] as num?)?.toDouble(),
      counts: ((j['counts'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, (v as num).toInt())),
      records: recs,
    );
  }
  int get absences => counts['ABSENT'] ?? 0;
}

class ReportSubject {
  ReportSubject({required this.name, required this.total, required this.grade, required this.remark, required this.position});
  final String name;
  final double? total;
  final String? grade;
  final String? remark;
  final int? position;
}

class ReportCard {
  ReportCard({required this.termId, required this.termName, required this.session, required this.className, required this.subjects, required this.average, required this.position, required this.outOf, required this.teacherRemark, required this.principalRemark, required this.attendanceRate, required this.nextTermBegins, this.overallGrade, this.promotion, this.verificationCode});
  final String? overallGrade;
  final String? promotion;
  final String? verificationCode;
  final String termId;
  final String termName;
  final String session;
  final String className;
  final List<ReportSubject> subjects;
  final double? average;
  final String? position;
  final int? outOf;
  final String? teacherRemark;
  final String? principalRemark;
  final double? attendanceRate;
  final String? nextTermBegins;

  factory ReportCard.fromJson(Map<String, dynamic> j) => ReportCard(
        termId: j['term']['id'],
        termName: j['term']['name'],
        session: j['term']['session'],
        className: j['class']['name'],
        subjects: (j['subjects'] as List)
            .map((s) => ReportSubject(name: s['name'], total: (s['total'] as num?)?.toDouble(), grade: s['grade'], remark: s['remark'], position: (s['position'] as num?)?.toInt()))
            .toList(),
        average: (j['summary']?['average'] as num?)?.toDouble(),
        position: j['summary']?['position'] as String?,
        outOf: (j['summary']?['outOf'] as num?)?.toInt(),
        teacherRemark: j['remarks']?['teacher'],
        principalRemark: j['remarks']?['principal'],
        attendanceRate: (j['attendance']?['rate'] as num?)?.toDouble(),
        nextTermBegins: j['nextTermBegins'],
        overallGrade: j['overallGrade']?['grade'] as String?,
        promotion: j['promotion'] as String?,
        verificationCode: j['verificationCode'] as String?,
      );
}

/// A child's average in one released term, for the progress chart.
class TermAverage {
  TermAverage({required this.term, required this.session, required this.className, required this.average, required this.position});
  final String term;
  final String session;
  final String className;
  final double? average;
  final String? position;
  factory TermAverage.fromJson(Map<String, dynamic> j) =>
      TermAverage(term: j['term'], session: j['session'], className: j['className'], average: (j['average'] as num?)?.toDouble(), position: j['position'] as String?);
}

/// One paper in the child's exam timetable.
class ExamPaper {
  ExamPaper({required this.subject, required this.date, required this.startTime, required this.minutes});
  final String subject;
  final String date;
  final String startTime;
  final int minutes;
  factory ExamPaper.fromJson(Map<String, dynamic> j) => ExamPaper(subject: j['subject'], date: j['date'], startTime: j['startTime'], minutes: (j['minutes'] as num).toInt());
}

/// A notice from a child's school.
class SchoolNotice {
  SchoolNotice({required this.title, required this.body, required this.school, required this.at});
  final String title;
  final String body;
  final String? school;
  final DateTime at;
  factory SchoolNotice.fromJson(Map<String, dynamic> j) => SchoolNotice(title: j['title'], body: j['body'], school: j['school'], at: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now());
}

class Child {
  Child({required this.id, required this.fullName, required this.firstName, required this.relationship, required this.schoolName, required this.className, required this.classTeacher, required this.learnerId, required this.attendance, required this.terms, required this.latestCard, this.progress = const [], this.exams = const [], this.examTerm});
  final List<TermAverage> progress;
  final List<ExamPaper> exams;
  final String? examTerm;
  final String id;
  final String fullName;
  final String firstName;
  final String relationship;
  final String? schoolName;
  final String? className;
  final String? classTeacher;
  final String learnerId;
  final ChildAttendance attendance;
  /// Terms with a released report card, newest first: (term id, "First term, 2026/2027").
  final List<(String, String)> terms;
  final ReportCard? latestCard;

  factory Child.fromJson(Map<String, dynamic> j) => Child(
        id: j['id'],
        fullName: j['fullName'],
        firstName: j['firstName'] ?? (j['fullName'] as String).split(' ').skip(1).firstOrNull ?? j['fullName'],
        relationship: j['relationship'] ?? '',
        schoolName: j['school']?['name'],
        className: j['currentClass']?['name'],
        classTeacher: j['classTeacher'],
        learnerId: j['learnerId'] ?? '',
        attendance: ChildAttendance.fromJson(j['attendance'] as Map<String, dynamic>?),
        terms: ((j['terms'] as List?) ?? []).where((t) => t['released'] == true).map((t) => (t['termId'] as String, '${t['name']}, ${t['session']}')).toList(),
        latestCard: j['latestCard'] == null ? null : ReportCard.fromJson(j['latestCard']),
        progress: ((j['progress'] as List?) ?? []).map((p) => TermAverage.fromJson(p)).toList(),
        exams: ((j['exams']?['papers'] as List?) ?? []).map((p) => ExamPaper.fromJson(p)).toList(),
        examTerm: j['exams']?['term']?['name'] as String?,
      );
}

class InboxItem {
  InboxItem({required this.id, required this.kind, required this.title, required this.body, required this.link, required this.read, required this.at});
  final String id;
  final String kind;
  final String title;
  final String body;
  final String? link;
  final bool read;
  final DateTime at;
  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: j['id'], kind: j['kind'], title: j['title'], body: j['body'], link: j['link'], read: j['read'] == true, at: DateTime.tryParse(j['at'] ?? '') ?? DateTime.now());

  /// The child a notification is about, from links like `/students/{id}` or `/report-card/{id}?term=...`.
  String? get childId => RegExp(r'^/(?:students|report-card)/([0-9a-f-]{36})').firstMatch(link ?? '')?.group(1);
}

class ParentData {
  ParentData({required this.userName, required this.children, required this.inbox, this.notices = const []});
  final List<SchoolNotice> notices;
  final String userName;
  final List<Child> children;
  final List<InboxItem> inbox;

  factory ParentData.fromJson(Map<String, dynamic> j, {Set<String> readHere = const {}}) => ParentData(
        userName: j['userName'] ?? '',
        children: ((j['children'] as List?) ?? []).map((c) => Child.fromJson(c)).toList(),
        inbox: ((j['inbox'] as List?) ?? []).map((n) {
          final i = InboxItem.fromJson(n);
          return readHere.contains(i.id) ? InboxItem(id: i.id, kind: i.kind, title: i.title, body: i.body, link: i.link, read: true, at: i.at) : i;
        }).toList(),
        notices: ((j['notices'] as List?) ?? []).map((n) => SchoolNotice.fromJson(n)).toList(),
      );
  int get unread => inbox.where((n) => !n.read).length;
}
