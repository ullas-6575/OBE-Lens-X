import 'dart:collection';

import '../models/marks_table_data.dart';
import 'models.dart';

int comparePoCodes(String a, String b) =>
    int.parse(a.substring(2)).compareTo(int.parse(b.substring(2)));

class OutcomeScore {
  final String code;
  final int eligible, attained;
  const OutcomeScore(this.code, this.eligible, this.attained);
  double? get percent => eligible == 0 ? null : attained * 100 / eligible;
}

class StudentAttainment {
  final String rollNo;
  final Map<String, int> outcomes;
  final String status;
  const StudentAttainment(this.rollNo, this.outcomes, this.status);
}

class AttainmentReport {
  final List<OutcomeScore> outcomes;
  final Map<String, double> poContribution;
  final int students, excluded;
  final List<String> issues;
  final List<StudentAttainment> studentRows;
  const AttainmentReport(this.outcomes, this.poContribution, this.students,
      this.excluded, this.issues,
      {this.studentRows = const []});
  bool get exportable => issues.isEmpty && outcomes.any((c) => c.eligible > 0);
}

/// Pure domain calculation. No Flutter, database, or recognizer dependencies.
class AttainmentCalculator {
  const AttainmentCalculator();
  AttainmentReport calculate(Course course, Exam exam, List<Json> results) {
    final issues = <String>[];
    final configurationError = exam.validate(course);
    if (configurationError != null) {
      return AttainmentReport(const [], const {}, 0, 0, [configurationError]);
    }
    final students = <String, Map<String, Json>>{};
    final invalidStudents = <String>{};
    for (final result in results) {
      final groups =
          students.putIfAbsent(result['roll_no'] as String, () => {});
      final group = result['table_type'] as String;
      if (groups.containsKey(group)) {
        issues.add('Duplicate group for ${result['roll_no']}.');
        invalidStudents.add(result['roll_no'] as String);
      }
      groups[group] = result;
      final marks = (result['marks'] as Map).map((q, cells) => MapEntry(
          q.toString(),
          (cells as Map).map((p, v) => MapEntry(p.toString(), v.toString()))));
      final validation = ScanContext(
              course, const Offering('', '', '', ''), exam, result['roll_no'])
          .validateMarks(group, marks);
      if (validation != null) {
        issues.add('${result['roll_no']}: $validation');
        invalidStudents.add(result['roll_no'] as String);
      }
      if (exam.countedQuestions(
              group, result['selected_questions'], result['marks'] as Map) ==
          null) {
        issues.add(
            '${result['roll_no']}: select three counted questions for Q$group.');
        invalidStudents.add(result['roll_no'] as String);
      }
    }
    var excluded = 0;
    final eligible = <String, int>{};
    final attained = <String, int>{};
    final studentRows = <StudentAttainment>[];
    final rolls = students.keys.toList()
      ..sort((a, b) {
        final first = int.tryParse(a), second = int.tryParse(b);
        if (first == null && second != null) return 1;
        if (first != null && second == null) return -1;
        final order = first != null && second != null
            ? first.compareTo(second)
            : a.compareTo(b);
        return order == 0 ? a.compareTo(b) : order;
      });
    for (final roll in rolls) {
      final groups = students[roll]!;
      if (invalidStudents.contains(roll)) {
        excluded++;
        studentRows.add(StudentAttainment(roll, const {}, 'Invalid marks'));
        continue;
      }
      if (!exam.requiredGroups.every(groups.containsKey)) {
        excluded++;
        studentRows.add(StudentAttainment(roll, const {}, 'Incomplete'));
        continue;
      }
      final earned = <String, double>{};
      final possible = <String, double>{};
      for (final q in exam.questions) {
        if (!exam
            .countedQuestions(q.group, groups[q.group]!['selected_questions'],
                groups[q.group]!['marks'] as Map)!
            .contains(q.question)) continue;
        final marks = groups[q.group]!['marks'] as Map;
        final value = (marks[q.question] as Map?)?[q.part]?.toString() ?? 'N/A';
        earned.update(q.co, (v) => v + MarksTableData.parseMarkValue(value),
            ifAbsent: () => MarksTableData.parseMarkValue(value));
        possible.update(q.co, (v) => v + q.maxMark,
            ifAbsent: () => q.maxMark.toDouble());
      }
      final studentOutcomes = <String, int>{};
      for (final co in possible.keys) {
        if (possible[co]! <= 0) continue;
        eligible.update(co, (n) => n + 1, ifAbsent: () => 1);
        final met =
            earned[co]! * 100 / possible[co]! >= exam.policy.scoreThreshold;
        studentOutcomes[co] = met ? 1 : 0;
        if (met) {
          attained.update(co, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      studentRows.add(StudentAttainment(roll, studentOutcomes, 'Eligible'));
    }
    final outcomes = course.outcomes
        .map((c) =>
            OutcomeScore(c.code, eligible[c.code] ?? 0, attained[c.code] ?? 0))
        .toList();
    final contributions = SplayTreeMap<String, List<double>>(comparePoCodes);
    for (final outcome in course.outcomes) {
      final score = outcomes.firstWhere((s) => s.code == outcome.code).percent;
      if (score == null) continue;
      for (final po in outcome.pos.toSet()) {
        contributions.putIfAbsent(po, () => []).add(score);
      }
    }
    return AttainmentReport(
        outcomes,
        {
          for (final e in contributions.entries)
            e.key: e.value.reduce((a, b) => a + b) / e.value.length,
        },
        students.length,
        excluded,
        issues,
        studentRows: studentRows);
  }
}
