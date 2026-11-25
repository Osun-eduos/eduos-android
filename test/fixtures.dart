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
