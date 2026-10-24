import '../models/marks_table_data.dart';
import 'models.dart';

class OutcomeScore {
  final String code;
  final int eligible, attained;
  const OutcomeScore(this.code, this.eligible, this.attained);
  double? get percent => eligible == 0 ? null : attained * 100 / eligible;
}

class AttainmentReport {
  final List<OutcomeScore> outcomes;
  final Map<String, double> poContribution;
  final int students, excluded;
  final List<String> issues;
  const AttainmentReport(this.outcomes, this.poContribution, this.students,
      this.excluded, this.issues);
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
    for (final result in results) {
      final groups =
          students.putIfAbsent(result['roll_no'] as String, () => {});
      final group = result['table_type'] as String;
      if (groups.containsKey(group)) {
        issues.add('Duplicate group for ${result['roll_no']}.');
      }
      groups[group] = result;
      final marks = (result['marks'] as Map).map((q, cells) => MapEntry(
          q.toString(),
          (cells as Map).map((p, v) => MapEntry(p.toString(), v.toString()))));
      final validation = ScanContext(
              course, const Offering('', '', '', ''), exam, result['roll_no'])
          .validateMarks(group, marks);
      if (validation != null) issues.add('${result['roll_no']}: $validation');
    }
    var excluded = 0;
    final eligible = <String, int>{};
    final attained = <String, int>{};
    for (final student in students.entries) {
      if (!exam.requiredGroups.every(student.value.containsKey)) {
        excluded++;
        if (!exam.policy.excludeIncomplete) {
          issues.add('${student.key}: missing table group.');
        }
        continue;
      }
      final earned = <String, double>{};
      final possible = <String, double>{};
      for (final q in exam.questions) {
        final marks = student.value[q.group]!['marks'] as Map;
        final value = (marks[q.question] as Map?)?[q.part]?.toString() ?? 'N/A';
        if (value == 'N/A' && (q.optional || exam.policy.excludeNA)) continue;
        earned.update(q.co, (v) => v + MarksTableData.parseMarkValue(value),
            ifAbsent: () => MarksTableData.parseMarkValue(value));
        possible.update(q.co, (v) => v + q.maxMark,
            ifAbsent: () => q.maxMark.toDouble());
      }
      for (final co in possible.keys) {
        if (possible[co]! <= 0) continue;
        eligible.update(co, (n) => n + 1, ifAbsent: () => 1);
        if (earned[co]! * 100 / possible[co]! >= exam.policy.scoreThreshold) {
          attained.update(co, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    final outcomes = course.outcomes
        .map((c) =>
            OutcomeScore(c.code, eligible[c.code] ?? 0, attained[c.code] ?? 0))
        .toList();
    final contributions = <String, List<double>>{};
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
        issues);
  }
}
