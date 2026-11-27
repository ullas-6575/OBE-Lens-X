import '../models/marks_table_data.dart';

typedef Json = Map<String, dynamic>;

/// An account can use the app only while it is approved.
enum RegistrationStatus {
  pending,
  approved,
  rejected;

  /// Reads the tri-state column, falling back to the legacy approved boolean on
  /// projects that have not applied the registration-status migration yet.
  static RegistrationStatus of(Json profile) => switch (profile['status']) {
        'approved' => approved,
        'rejected' => rejected,
        'pending' => pending,
        _ => profile['approved'] == true ? approved : pending,
      };
}

class CourseOutcome {
  static const codes = ['CO1', 'CO2', 'CO3', 'CO4'];

  final String code;
  final String description;
  final List<String> pos;
  const CourseOutcome(this.code, this.description, this.pos);
  factory CourseOutcome.fromJson(Json j) => CourseOutcome(j['code'] as String,
      j['description'] as String, List<String>.from(j['pos'] as List));
  Json toJson() => {'code': code, 'description': description, 'pos': pos};
}

class Course {
  final String id, code, title;
  final bool archived;
  final List<CourseOutcome> outcomes;
  const Course(
      {required this.id,
      required this.code,
      required this.title,
      this.archived = false,
      this.outcomes = const []});
  factory Course.fromJson(Json j) => Course(
      id: j['id'],
      code: j['code'],
      title: j['title'],
      archived: j['archived'],
      outcomes: (j['outcomes'] as List)
          .map((e) => CourseOutcome.fromJson(Json.from(e)))
          .toList());
}

class Offering {
  final String id, courseId, year, term;
  const Offering(this.id, this.courseId, this.year, this.term);
  factory Offering.fromJson(Json j) =>
      Offering(j['id'], j['course_id'], j['academic_year'], j['term']);
  String get label => '$year · $term';
}

class QuestionMapping {
  final String question, part, co;
  final int maxMark;
  const QuestionMapping(this.question, this.part, this.co, this.maxMark);
  String get key => '$question:$part';
  String get group => int.parse(question) <= 4 ? '1-4' : '5-8';
  factory QuestionMapping.fromJson(Json j) =>
      QuestionMapping(j['question'], j['part'], j['co'], j['max_mark']);
  Json toJson() =>
      {'question': question, 'part': part, 'co': co, 'max_mark': maxMark};
}

/// Policy is explicit and versioned with each exam. Checkbox PO links are unweighted.
class AttainmentPolicy {
  static const defaultLevelBounds = [55.0, 65.0, 75.0, 85.0];

  // Keep targetPercent in saved JSON for compatibility with existing databases.
  final double scoreThreshold, targetPercent;
  final List<double> levelBounds;
  const AttainmentPolicy(
      {this.scoreThreshold = 50,
      this.targetPercent = 60,
      this.levelBounds = defaultLevelBounds});
  factory AttainmentPolicy.fromJson(Json j) => AttainmentPolicy(
      scoreThreshold: (j['score_threshold'] as num).toDouble(),
      targetPercent: (j['target_percent'] as num?)?.toDouble() ?? 60,
      levelBounds: j['level_bounds'] == null
          ? defaultLevelBounds
          : (j['level_bounds'] as List)
              .map((value) => (value as num).toDouble())
              .toList());
  Json toJson() => {
        'score_threshold': scoreThreshold,
        'target_percent': targetPercent,
        'level_bounds': levelBounds,
      };

  String? validate() {
    if (!scoreThreshold.isFinite ||
        scoreThreshold < 0 ||
        scoreThreshold > 100) {
      return 'Enter a student score threshold between 0 and 100.';
    }
    if (levelBounds.length != 4) return 'Enter four attainment level cutoffs.';
    for (var index = 0; index < levelBounds.length; index++) {
      final bound = levelBounds[index];
      if (!bound.isFinite ||
          bound < 0 ||
          bound >= 100 ||
          (index > 0 && bound <= levelBounds[index - 1])) {
        return 'Level cutoffs must increase from L0 to L3 and be between 0 and less than 100.';
      }
    }
    return null;
  }

  String level(double? percent) {
    if (percent == null) return 'N/A';
    final index = levelBounds.indexWhere((bound) => percent <= bound);
    return 'L${index < 0 ? 4 : index}';
  }

  String get levelDescription => [
        'L0: 0–${levelBounds[0]}%',
        for (var index = 1; index < levelBounds.length; index++)
          'L$index: >${levelBounds[index - 1]}–${levelBounds[index]}%',
        'L4: >${levelBounds.last}%',
      ].join('; ');
}

class Exam {
  final String id, offeringId, name;
  final List<QuestionMapping> questions;
  final List<String> requiredGroups;
  final AttainmentPolicy policy;
  final int revision;
  const Exam(
      {required this.id,
      required this.offeringId,
      required this.name,
      this.questions = const [],
      this.requiredGroups = const ['1-4', '5-8'],
      this.policy = const AttainmentPolicy(),
      this.revision = 1});
  factory Exam.fromJson(Json j) => Exam(
      id: j['id'],
      offeringId: j['offering_id'],
      name: j['name'],
      revision: j['revision'],
      questions: (j['questions'] as List)
          .map((e) => QuestionMapping.fromJson(Json.from(e)))
          .toList(),
      requiredGroups: List<String>.from(j['required_groups']),
      policy: AttainmentPolicy.fromJson(Json.from(j['policy'])));

  String? validate(Course course) {
    final policyError = policy.validate();
    if (policyError != null) return policyError;
    if (questions.isEmpty) {
      return 'Configure questions and CO mappings before scanning.';
    }
    if (requiredGroups.isEmpty) {
      return 'Select at least one required table group.';
    }
    final keys = <String>{};
    for (final q in questions) {
      if (!keys.add(q.key)) return 'Duplicate question part: ${q.key}.';
      if (!['1', '2', '3', '4', '5', '6', '7', '8'].contains(q.question) ||
          !MarksTableData.parts.contains(q.part) ||
          q.maxMark < 1 ||
          q.maxMark > 99 ||
          !CourseOutcome.codes.contains(q.co)) {
        return 'Every question needs a valid part, maximum (1–99), and course outcome.';
      }
      if (!requiredGroups.contains(q.group)) {
        return 'Enable group ${q.group} for Q${q.question}.';
      }
    }
    for (final group in requiredGroups) {
      if (!questions.any((q) => q.group == group)) {
        return 'Add mappings for group $group.';
      }
    }
    return null;
  }
}

class ScanContext {
  final Course course;
  final Offering offering;
  final Exam exam;
  final String rollNo;
  const ScanContext(this.course, this.offering, this.exam, this.rollNo);
  String get label =>
      '${course.code} · ${offering.label} · ${exam.name} · $rollNo';
  String? validateMarks(String group, Map<String, Map<String, String>> marks) {
    if (!exam.requiredGroups.contains(group)) {
      return 'This group is not used by the exam.';
    }
    for (final column in marks.entries) {
      for (final cell in column.value.entries) {
        final mappings = exam.questions
            .where((q) => q.question == column.key && q.part == cell.key);
        final value = cell.value;
        if (value == 'N/A') continue;
        if (!MarksTableData.isNumericMark(value)) {
          return 'Q${column.key}${cell.key} must be an integer or N/A.';
        }
        if (mappings.isEmpty) {
          return 'Q${column.key}${cell.key} has marks but no mapping.';
        }
        if (mappings.isNotEmpty && int.parse(value) > mappings.first.maxMark) {
          return 'Q${column.key}${cell.key} exceeds its maximum of ${mappings.first.maxMark}.';
        }
      }
    }
    return null;
  }
}
