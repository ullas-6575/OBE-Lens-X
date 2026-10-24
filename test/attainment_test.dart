import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/workflow/attainment.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/report_export.dart';
import 'support/workflow_fakes.dart';

Json row(String roll, String value, {String group = '1-4'}) => {
      'exam_id': 'exam',
      'roll_no': roll,
      'table_type': group,
      'marks': MarksTableData.empty(tableType: group).cellMarks
        ..[group == '1-4' ? '1' : '5']!['a'] = value,
    };
void main() {
  const calculator = AttainmentCalculator();
  test('Threshold includes equality and PO links carry equal CO contributions',
      () {
    final report = calculator.calculate(sampleCourse, sampleExam,
        [row('1', '5'), row('2', '4'), row('3', 'N/A')]);
    expect(report.outcomes.single.eligible, 3);
    expect(report.outcomes.single.attained, 1);
    expect(report.poContribution['PO1'], closeTo(100 / 3, .0001));
  });
  test(
      'N/A exclusion changes denominator; all-excluded students are ineligible',
      () {
    const exam = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Final',
        requiredGroups: ['1-4'],
        questions: [QuestionMapping('1', 'a', 'CO1', 10)],
        policy: AttainmentPolicy(excludeNA: true));
    final report = calculator
        .calculate(sampleCourse, exam, [row('1', '5'), row('2', 'N/A')]);
    expect(report.outcomes.single.eligible, 1);
    expect(report.outcomes.single.percent, 100);
  });
  test(
      'Incomplete scripts are excluded or block export according to exam policy',
      () {
    const questions = [
      QuestionMapping('1', 'a', 'CO1', 10),
      QuestionMapping('5', 'a', 'CO1', 10)
    ];
    const exclude = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Final',
        questions: questions);
    const block = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Final',
        questions: questions,
        policy: AttainmentPolicy(excludeIncomplete: false));
    final rows = [
      row('complete', '8'),
      row('complete', '8', group: '5-8'),
      row('partial', '9')
    ];
    final report = calculator.calculate(sampleCourse, exclude, rows);
    expect(report.excluded, 1);
    expect(report.outcomes.single.eligible, 1);
    expect(report.exportable, true);
    expect(calculator.calculate(sampleCourse, block, rows).exportable, false);
  });
  test('Optional N/A is excluded even when required N/A counts zero', () {
    const exam = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Final',
        requiredGroups: [
          '1-4'
        ],
        questions: [
          QuestionMapping('1', 'a', 'CO1', 10),
          QuestionMapping('1', 'b', 'CO1', 20, optional: true)
        ]);
    expect(
        calculator
            .calculate(sampleCourse, exam, [row('1', '5')])
            .outcomes
            .single
            .percent,
        100);
  });
  test('Changed maxima, unmapped marks and duplicates block reports', () {
    expect(
        calculator
            .calculate(sampleCourse, sampleExam, [row('1', '11')]).exportable,
        false);
    final unmapped = row('1', '5');
    (unmapped['marks'] as Map)['2']['a'] = '1';
    expect(
        calculator.calculate(sampleCourse, sampleExam, [unmapped]).exportable,
        false);
    expect(
        calculator.calculate(sampleCourse, sampleExam,
            [row('1', '5'), row('1', '6')]).exportable,
        false);
  });
  test('No eligible results never produces a misleading zero-percent report',
      () {
    final report = calculator.calculate(sampleCourse, sampleExam, []);
    expect(report.outcomes.single.percent, isNull);
    expect(report.exportable, false);
  });
  test('Spreadsheet export escapes quotes and neutralizes formula cells', () {
    final csv = reportCsv([
      ['=HYPERLINK("x")', 'line, one', 'normal', '  +CMD']
    ]);
    expect(csv, contains('"\'=HYPERLINK(""x"")"'));
    expect(csv, contains('"line, one"'));
    expect(csv, contains('"\'  +CMD"'));
  });
}
