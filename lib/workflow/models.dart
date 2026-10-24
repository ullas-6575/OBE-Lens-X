import '../models/marks_table_data.dart';

typedef Json = Map<String, dynamic>;

class CourseOutcome {
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
  final bool optional;
  const QuestionMapping(this.question, this.part, this.co, this.maxMark,
      {this.optional = false});
  String get key => '$question:$part';
  String get group => int.parse(question) <= 4 ? '1-4' : '5-8';
  factory QuestionMapping.fromJson(Json j) =>
      QuestionMapping(j['question'], j['part'], j['co'], j['max_mark'],
          optional: j['optional'] == true);
  Json toJson() => {
        'question': question,
        'part': part,
        'co': co,
        'max_mark': maxMark,
        'optional': optional
      };
}

/// Policy is explicit and versioned with each exam. Checkbox PO links are unweighted.
class AttainmentPolicy {
  final double scoreThreshold, targetPercent;
  final bool excludeIncomplete, excludeNA;
  const AttainmentPolicy(
      {this.scoreThreshold = 50,
      this.targetPercent = 60,
      this.excludeIncomplete = true,
      this.excludeNA = false});
  factory AttainmentPolicy.fromJson(Json j) => AttainmentPolicy(
      scoreThreshold: (j['score_threshold'] as num).toDouble(),
      targetPercent: (j['target_percent'] as num).toDouble(),
      excludeIncomplete: j['exclude_incomplete'],
      excludeNA: j['exclude_na']);
  Json toJson() => {
        'score_threshold': scoreThreshold,
        'target_percent': targetPercent,
        'exclude_incomplete': excludeIncomplete,
        'exclude_na': excludeNA
      };
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
          !course.outcomes.any((c) => c.code == q.co)) {
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
        if (int.parse(value) > mappings.first.maxMark) {
          return 'Q${column.key}${cell.key} exceeds its maximum of ${mappings.first.maxMark}.';
        }
      }
    }
    return null;
  }
}
