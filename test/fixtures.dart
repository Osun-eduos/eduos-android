import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:eduos_mobile/src/store/local_store.dart';

const classId = 'c-jss2a';
const mathsId = 'cs-mth';

Map<String, dynamic> student(String id, String name, {String admitted = '2026-09-14'}) =>
    {'id': id, 'learnerId': 'OSN-26-$id', 'fullName': name, 'sex': 'F', 'admittedOn': admitted};

/// A snapshot as eduos-sync sends it, for a teacher of JSS 2A who teaches maths there.
Map<String, dynamic> snapshotBody({String today = '2026-11-25', String sheetStatus = 'DRAFT', bool released = false, String level = 'JSS_2', String sssGrading = 'WAEC'}) {
  final students = [student('s1', 'Adeleke Ayomide'), student('s2', 'Babalola Tunde'), student('s3', 'Zaki New', admitted: today)];
  return {
    'today': today,
    'attendance': {'teacherEditDays': 7},
    'grading': {
      'scales': {
        'BASIC': [
          {'min': 70, 'grade': 'A', 'remark': 'Excellent'},
          {'min': 60, 'grade': 'B', 'remark': 'Very good'},
          {'min': 50, 'grade': 'C', 'remark': 'Good'},
          {'min': 45, 'grade': 'D', 'remark': 'Fair'},
          {'min': 40, 'grade': 'E', 'remark': 'Pass'},
          {'min': 0, 'grade': 'F', 'remark': 'Fail'},
        ],
        'SSS': [
          {'min': 75, 'grade': 'A1', 'remark': 'Excellent'},
          {'min': 70, 'grade': 'B2', 'remark': 'Very good'},
          {'min': 0, 'grade': 'F9', 'remark': 'Fail'},
        ],
      },
    },
    'snapshot': {
      'generatedAt': '2026-11-25T07:00:00Z',
      'user': {'id': 'u1', 'fullName': 'Tunde Olaniyan', 'role': 'TEACHER'},
      'school': {'id': 'sc1', 'name': 'Osogbo Grammar School'},
      'session': {'id': 'se1', 'name': '2026/2027', 'startDate': '2026-09-14', 'endDate': '2027-07-16'},
      'term': {
        'id': 't1', 'name': 'First term, 2026/2027', 'number': 1, 'startDate': '2026-09-14', 'endDate': '2026-12-18', 'sssGrading': sssGrading,
        'components': [
          {'key': 'CA1', 'label': 'CA 1', 'max': 20},
          {'key': 'CA2', 'label': 'CA 2', 'max': 20},
          {'key': 'EXAM', 'label': 'Exam', 'max': 60},
        ],
      },
      'classes': [
        {
          'id': classId, 'name': 'JSS 2A', 'level': level, 'students': students,
          'registers': [
            {'date': '2026-11-24', 'marks': [
              {'studentId': 's1', 'status': 'PRESENT', 'note': null},
              {'studentId': 's2', 'status': 'ABSENT', 'note': 'Sick'},
            ]},
          ],
        },
      ],
      'holidays': [
        {'name': 'Mid-term break', 'startDate': '2026-11-19', 'endDate': '2026-11-20'},
      ],
      'subjects': [
        {
          'classSubjectId': mathsId, 'code': 'MTH', 'name': 'Mathematics', 'classId': classId, 'className': 'JSS 2A', 'level': level,
          'released': released, 'students': students,
          'sheet': {'id': 'sheet1', 'status': sheetStatus, 'returnNote': sheetStatus == 'RETURNED' ? 'Check Tunde' : null, 'scores': [
            {'studentId': 's1', 'marks': {'CA1': 18, 'CA2': 17, 'EXAM': 50}, 'total': 85},
          ]},
        },
      ],
    },
  };
}

Future<LocalStore> memoryStore() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: LocalStore.create, singleInstance: false));
  return LocalStore(db);
}

/// What an inspector's phone keeps after a sync: two schools in Osogbo, the checklist and one earlier visit.
Map<String, dynamic> inspectorMeta(Map<String, dynamic> template) => {
      'schools': [
        {'id': 'sch-1', 'name': 'Osogbo Grammar School', 'code': 'OS/OSG/COM/0001', 'lga': 'Osogbo'},
        {'id': 'sch-2', 'name': 'Baptist High School', 'code': 'OS/OSG/COM/0002', 'lga': 'Osogbo'},
      ],
      'template': template,
      'recent': [
        {'id': 'srv-0', 'clientId': 'old', 'school': {'name': 'Baptist High School'}, 'visitedOn': '2026-11-10', 'overall': 'FAIR', 'issues': [{'text': 'No first aid box'}], 'photoCount': 2},
      ],
      'userName': 'Kola Adeyemi',
      'lga': 'Osogbo',
    };

/// Every checklist question answered for a school in good condition.
Map<String, Map<String, Object?>> goodAnswers() => {
      'classrooms': {'total': 12, 'usable': 12, 'condition': 'GOOD', 'roofLeaks': false, 'enoughSeats': true, 'boards': 'GOOD'},
      'toilets': {'girls': 4, 'boys': 4, 'staff': 2, 'working': 10, 'condition': 'GOOD', 'handwashing': true},
      'water': {'source': 'BOREHOLE', 'working': true, 'safe': true},
      'power': {'source': 'SOLAR', 'working': true},
      'safety': {'fence': 'FULL', 'gate': true, 'firstAid': true, 'fireExtinguisher': true, 'hazards': false},
      'facilities': {'library': true, 'laboratory': false, 'ict': false, 'playground': true},
    };

const childId = '11111111-2222-4333-8444-555555555555';
const termId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

/// What the API returns to a parent, by path.
Map<String, Object> parentApi() => {
      '/my/children': [
        {
          'id': childId, 'learnerId': 'OSN-26-000001', 'fullName': 'Adewale Toluwani Grace', 'firstName': 'Toluwani', 'surname': 'Adewale',
          'relationship': 'Mother', 'classTeacher': 'Mrs Akinola', 'school': {'name': 'Osogbo Grammar School'}, 'currentClass': {'name': 'JSS 1A'},
        },
      ],
      '/attendance/students/$childId': {
        'counts': {'PRESENT': 18, 'LATE': 1, 'ABSENT': 1, 'EXCUSED': 0}, 'rate': 95,
        'records': [
          {'date': '2026-11-24', 'status': 'PRESENT', 'note': null},
          {'date': '2026-11-25', 'status': 'ABSENT', 'note': null},
        ],
      },
      '/report-cards/$childId/terms': [
        {'termId': termId, 'name': 'First term', 'session': '2026/2027', 'className': 'JSS 1A', 'released': true},
      ],
      '/report-cards/$childId': {
        'term': {'id': termId, 'name': 'First term', 'session': '2026/2027'},
        'class': {'name': 'JSS 1A'},
        'subjects': [
          {'name': 'Mathematics', 'total': 78, 'grade': 'A', 'remark': 'Excellent', 'position': 2},
          {'name': 'English', 'total': 64, 'grade': 'B', 'remark': 'Very good', 'position': 5},
        ],
        'summary': {'average': 71, 'position': '3rd', 'outOf': 38},
        'remarks': {'teacher': 'A hard-working pupil.', 'principal': null},
        'attendance': {'rate': 95},
        'nextTermBegins': '2027-01-05',
      },
      '/notifications': {
        'unread': 2,
        'items': [
          {'id': 'n-1', 'kind': 'RESULTS', 'title': 'Report card ready', 'body': "Toluwani Adewale's First term report card for 2026/2027 is ready.", 'link': '/report-card/$childId?term=$termId', 'read': false, 'at': '2026-11-25T14:00:00Z'},
          {'id': 'n-2', 'kind': 'ABSENCE', 'title': 'Toluwani was absent today', 'body': 'Toluwani Adewale was marked absent.', 'link': '/students/$childId', 'read': false, 'at': '2026-11-25T08:30:00Z'},
          {'id': 'n-3', 'kind': 'NOTICE', 'title': 'Inter-house sports', 'body': 'Osogbo Grammar School: Sports day is Friday.', 'link': '/notifications', 'read': true, 'at': '2026-11-20T08:30:00Z'},
        ],
      },
    };
