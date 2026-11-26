// The inspection checklist as the API sends it, the inspector's schools and recent visits, and the checks the
// phone makes before an inspection is submitted (the API checks again).

class ChecklistItem {
  ChecklistItem({required this.key, required this.label, required this.type, this.options = const [], this.hint});
  final String key;
  final String label;
  /// count, rating, yesno or choice.
  final String type;
  final List<(String, String)> options;
  final String? hint;
}

class ChecklistSection {
  ChecklistSection({required this.key, required this.title, required this.items});
  final String key;
  final String title;
  final List<ChecklistItem> items;
}

class Checklist {
  Checklist({required this.version, required this.sections, required this.ratings});
  final int version;
  final List<ChecklistSection> sections;
  final List<(String, String)> ratings;

  static List<(String, String)> _opts(Object? l) => ((l as List?) ?? []).map((o) => (o['value'] as String, o['label'] as String)).toList();

  factory Checklist.fromJson(Map<String, dynamic> j) {
    final ratings = _opts(j['ratings']);
    return Checklist(
      version: j['version'] as int,
      ratings: ratings,
      sections: (j['sections'] as List)
          .map((s) => ChecklistSection(
                key: s['key'],
                title: s['title'],
                items: (s['items'] as List)
                    .map((i) => ChecklistItem(key: i['key'], label: i['label'], type: i['type'], hint: i['hint'], options: i['type'] == 'rating' ? ratings : _opts(i['options'])))
                    .toList(),
              ))
          .toList(),
    );
  }

  /// What is still missing or inconsistent, in words. Empty when the inspection can be submitted.
  List<String> problems(Map<String, Map<String, Object?>> answers) {
    final out = <String>[];
    for (final s in sections) {
      final missing = s.items.where((i) => answers[s.key]?[i.key] == null).length;
      if (missing > 0) out.add('${s.title}: $missing question${missing == 1 ? '' : 's'} not answered');
    }
    int n(String s, String i) => (answers[s]?[i] as int?) ?? 0;
    if (out.isEmpty) {
      if (n('classrooms', 'usable') > n('classrooms', 'total')) out.add('Classrooms: more safe classrooms than classrooms');
      if (n('toilets', 'working') > n('toilets', 'girls') + n('toilets', 'boys') + n('toilets', 'staff')) out.add('Toilets: more working toilets than toilets');
    }
    return out;
  }
}

class SchoolRef {
  SchoolRef({required this.id, required this.name, required this.code, required this.lga});
  final String id;
  final String name;
  final String code;
  final String lga;
  factory SchoolRef.fromJson(Map<String, dynamic> j) => SchoolRef(id: j['id'], name: j['name'], code: j['code'], lga: j['lga']);
}

class RecentInspection {
  RecentInspection({required this.id, required this.clientId, required this.schoolName, required this.visitedOn, required this.overall, required this.issues, required this.photoCount});
  final String id;
  final String clientId;
  final String schoolName;
  final String visitedOn;
  final String overall;
  final List<String> issues;
  final int photoCount;
  factory RecentInspection.fromJson(Map<String, dynamic> j) => RecentInspection(
        id: j['id'],
        clientId: j['clientId'] ?? '',
        schoolName: j['school']['name'],
        visitedOn: j['visitedOn'],
        overall: j['overall'],
        issues: ((j['issues'] as List?) ?? []).map((i) => i['text'] as String).toList(),
        photoCount: j['photoCount'] ?? 0,
      );
}

/// What an inspector works from offline: their schools, the checklist and their recent visits.
class InspectorData {
  InspectorData({required this.schools, required this.checklist, required this.recent, required this.userName, this.lga});
  final List<SchoolRef> schools;
  final Checklist checklist;
  final List<RecentInspection> recent;
  final String userName;
  final String? lga;

  factory InspectorData.fromJson(Map<String, dynamic> j) => InspectorData(
        schools: (j['schools'] as List).map((s) => SchoolRef.fromJson(s)).toList(),
        checklist: Checklist.fromJson(j['template']),
        recent: (j['recent'] as List).map((r) => RecentInspection.fromJson(r)).toList(),
        userName: j['userName'] ?? '',
        lga: j['lga'],
      );
}

const overallText = {'GOOD': 'Good', 'FAIR': 'Fair', 'POOR': 'Poor', 'CRITICAL': 'Critical'};

/// Roles that record inspections in the app.
const inspectorRoles = {'INSPECTOR', 'LGA_OFFICER'};
