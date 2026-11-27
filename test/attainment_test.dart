import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/workflow/attainment.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/report_export.dart';
import 'package:my_app/workflow/report_page.dart';
import 'support/workflow_fakes.dart';

Json row(String roll, String value, {String group = '1-4'}) => {
      'exam_id': 'exam',
      'roll_no': roll,
      'table_type': group,
      'marks': MarksTableData.empty(tableType: group).cellMarks
        ..[group == '1-4' ? '1' : '5']!['a'] = value,
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const calculator = AttainmentCalculator();
  test('Level boundaries are inclusive and configurable without rounding', () {
    const policy = AttainmentPolicy();
    for (final entry in <double, String>{
      0: 'L0',
      55: 'L0',
      55.01: 'L1',
      56: 'L1',
      65: 'L1',
      65.01: 'L2',
      75: 'L2',
      75.01: 'L3',
      85: 'L3',
      85.01: 'L4',
      100: 'L4',
    }.entries) {
      expect(policy.level(entry.key), entry.value, reason: '${entry.key}%');
    }
    expect(policy.level(null), 'N/A');
    const custom = AttainmentPolicy(levelBounds: [40, 60, 70, 90]);
    expect(custom.level(55), 'L1');
    expect(custom.level(85), 'L3');
    expect(AttainmentPolicy.fromJson(custom.toJson()).levelBounds,
        custom.levelBounds);
    expect(
        AttainmentPolicy.fromJson({'score_threshold': 50, 'target_percent': 60})
            .levelBounds,
        AttainmentPolicy.defaultLevelBounds);
  });
  test(
      'Invalid thresholds and overlapping or missing level bands block reports',
      () {
    for (final policy in [
      const AttainmentPolicy(scoreThreshold: -1),
      const AttainmentPolicy(scoreThreshold: 101),
      const AttainmentPolicy(scoreThreshold: double.nan),
      const AttainmentPolicy(levelBounds: [55, 55, 75, 85]),
      const AttainmentPolicy(levelBounds: [55, 65, 60, 85]),
      const AttainmentPolicy(levelBounds: [55, 65, 75, 100]),
      const AttainmentPolicy(levelBounds: [-1, 65, 75, 85]),
      const AttainmentPolicy(levelBounds: [55, 65, 75, double.infinity]),
      const AttainmentPolicy(levelBounds: [55, 65, 75]),
    ]) {
      final exam = Exam(
          id: sampleExam.id,
          offeringId: sampleExam.offeringId,
          name: sampleExam.name,
          questions: sampleExam.questions,
          requiredGroups: sampleExam.requiredGroups,
          policy: policy);
      final report = calculator.calculate(sampleCourse, exam, [row('1', '5')]);
      expect(report.exportable, false);
      expect(report.issues, isNotEmpty);
    }
  });
  test(
      'Student CO values combine mapped parts and use the configured threshold',
      () {
    const course =
        Course(id: 'course', code: 'CSE3200', title: 'Course', outcomes: [
      CourseOutcome('CO1', 'CO1', ['PO1']),
      CourseOutcome('CO2', 'CO2', []),
      CourseOutcome('CO3', 'CO3', []),
      CourseOutcome('CO4', 'CO4', []),
    ]);
    const exam = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Final',
        requiredGroups: ['1-4'],
        policy: AttainmentPolicy(scoreThreshold: 75),
        questions: [
          QuestionMapping('1', 'a', 'CO1', 10),
          QuestionMapping('1', 'b', 'CO1', 10),
          QuestionMapping('2', 'a', 'CO2', 10),
          QuestionMapping('3', 'a', 'CO3', 10),
          QuestionMapping('4', 'a', 'CO4', 10),
        ]);
    final result = row('1', '10')..['selected_questions'] = ['1', '2', '3'];
    final marks = result['marks'] as Map;
    marks['1']['b'] = '5';
    marks['2']['a'] = '7';
    marks['3']['a'] = '0';
    marks['4']['a'] = '10';
    final report = calculator.calculate(course, exam, [result]);
    expect(report.studentRows.single.outcomes, {'CO1': 1, 'CO2': 0, 'CO3': 0});
    expect(report.outcomes.map((score) => score.percent), [100, 0, 0, null]);
    expect(report.poContribution['PO1'], 100);
  });
  test('Report and spreadsheet include every roll and per-CO levels', () async {
    final repo = seededRepository()
      ..resultRows.addAll([row('10', '4'), row('2', '5'), row('1', 'N/A')]);
    final report =
        await loadExamReport(repo, sampleCourse, sampleOffering, sampleExam);
    final header = report.rows.indexWhere((row) => row.first == 'Roll no');
    expect(report.rows[header], ['Roll no', 'CO1', 'CO2', 'CO3', 'CO4']);
    expect(report.rows.sublist(header + 1, header + 4), [
      ['1', '0', 'N/A', 'N/A', 'N/A'],
      ['2', '1', 'N/A', 'N/A', 'N/A'],
      ['10', '0', 'N/A', 'N/A', 'N/A'],
    ]);
    expect(report.rows, contains(equals(['CO1', '3', '1', '33.33', 'L0'])));
    expect(report.rows, contains(equals(['PO1', '33.33', 'L0'])));
    final excel = reportExcelXml(report.rows);
    expect(RegExp('<Worksheet ').allMatches(excel).length, 4);
    expect(excel, contains('<Worksheet ss:Name="Student CO attainment">'));
    expect(excel, contains('<Worksheet ss:Name="CO attainment">'));
    expect(excel, contains('<Worksheet ss:Name="PO contributions">'));
    expect(excel, contains('<Data ss:Type="String">Roll no</Data>'));
    expect(excel, contains('<Data ss:Type="String">33.33</Data>'));
    expect(RegExp('<Row>').allMatches(excel).length, report.rows.length);
  });
  test('PO contribution rows are ordered by PO number in reports and exports',
      () async {
    const course =
        Course(id: 'course', code: 'CSE3200', title: 'Course', outcomes: [
      CourseOutcome('CO1', 'CO1', ['PO12', 'PO2', 'PO10', 'PO1']),
    ]);
    final repo = seededRepository()
      ..courseRows[0] = course
      ..resultRows.add(row('1', '5'));
    final snapshot =
        await loadExamReport(repo, course, sampleOffering, sampleExam);
    expect(snapshot.attainment!.poContribution.keys,
        ['PO1', 'PO2', 'PO10', 'PO12']);
    final poHeader = snapshot.rows.indexWhere((row) => row.first == 'PO');
    expect(snapshot.rows.skip(poHeader + 1).map((row) => row.first),
        ['PO1', 'PO2', 'PO10', 'PO12']);
  });
  test('Excel export supports uneven metadata and outcome rows', () {
    final excel = reportExcelXml([
      ['Course', 'CSE3200 · Software Engineering'],
      ['CO', 'Eligible', 'Attained', 'Attainment %', 'Level'],
      ['CO1', '2', '1', '50', 'L0'],
    ]);
    expect(excel, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(excel, contains('urn:schemas-microsoft-com:office:spreadsheet'));
    expect(RegExp('<Row>').allMatches(excel).length, 3);
    expect(excel, contains('CSE3200 · Software Engineering'));
  });
  test('Attainment workbook separates data types and keeps metadata together',
      () {
    final excel = reportExcelXml([
      ['Course', 'CSE3200'],
      ['Score threshold', '50%'],
      ['Roll no', 'CO1', 'CO2', 'CO3', 'CO4'],
      ['001', '1', '0', 'N/A', '1'],
      ['CO', 'Eligible', 'Attained', 'Attainment %', 'Level'],
      ['CO1', '1', '1', '100', 'L4'],
      ['Course PO contribution', 'Equal mean of linked CO percentages'],
      ['PO', 'Contribution %', 'Level'],
      ['PO1', '100', 'L4'],
      ['Generated at (UTC)', '2026-11-27T12:00:00Z'],
    ]);
    final sheets = {
      for (final match in RegExp(
              r'<Worksheet ss:Name="([^"]+)"><Table>(.*?)</Table></Worksheet>')
          .allMatches(excel))
        match.group(1)!: match.group(2)!,
    };
    expect(sheets.keys, [
      'Report details',
      'Student CO attainment',
      'CO attainment',
      'PO contributions',
    ]);
    expect(sheets['Report details'], contains('Generated at (UTC)'));
    expect(sheets['Report details'], contains('CSE3200'));
    expect(sheets['Student CO attainment'], contains('>001</Data>'));
    expect(sheets['Student CO attainment'], isNot(contains('>PO1</Data>')));
    expect(sheets['CO attainment'], contains('>Eligible</Data>'));
    expect(sheets['CO attainment'], isNot(contains('>001</Data>')));
    expect(sheets['PO contributions'], contains('>PO1</Data>'));
    expect(sheets['PO contributions'], isNot(contains('Generated at (UTC)')));
    expect(RegExp('<Workbook ').allMatches(excel).length, 1);
    expect(RegExp('<Row>').allMatches(excel).length, 10);
  });
  test('Threshold includes equality and PO links carry equal CO contributions',
      () {
    final report = calculator.calculate(sampleCourse, sampleExam,
        [row('1', '5'), row('2', '4'), row('3', 'N/A')]);
    expect(report.outcomes.single.eligible, 3);
    expect(report.outcomes.single.attained, 1);
    expect(report.studentRows.map((s) => s.outcomes['CO1']), [1, 0, 0]);
    expect(report.poContribution['PO1'], closeTo(100 / 3, .0001));
  });
  test('N/A marks count as zero toward the maximum marks', () {
    const exam = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Final',
        requiredGroups: ['1-4'],
        questions: [QuestionMapping('1', 'a', 'CO1', 10)]);
    final report = calculator
        .calculate(sampleCourse, exam, [row('1', '5'), row('2', 'N/A')]);
    expect(report.outcomes.single.eligible, 2);
    expect(report.outcomes.single.percent, 50);
  });
  test('Incomplete scripts are always excluded from attainment reports', () {
    const questions = [
      QuestionMapping('1', 'a', 'CO1', 10),
      QuestionMapping('5', 'a', 'CO1', 10)
    ];
    const exam = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Final',
        questions: questions);
    final rows = [
      row('complete', '8'),
      row('complete', '8', group: '5-8'),
      row('partial', '9')
    ];
    final report = calculator.calculate(sampleCourse, exam, rows);
    expect(report.excluded, 1);
    expect(report.studentRows.map((s) => s.rollNo), ['complete', 'partial']);
    expect(report.studentRows.last.status, 'Incomplete');
    expect(report.studentRows.last.outcomes, isEmpty);
    expect(report.outcomes.single.eligible, 1);
    expect(report.exportable, true);
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
    expect(report.studentRows, isEmpty);
  });
  test('Excel export escapes XML and stores formulas and roll numbers as text',
      () {
    final excel = reportExcelXml([
      ['=HYPERLINK("x")', 'A&B <Course>', '001', '  +CMD']
    ]);
    expect(excel, contains('<Data ss:Type="String">=HYPERLINK("x")</Data>'));
    expect(excel, contains('A&amp;B &lt;Course&gt;'));
    expect(excel, contains('<Data ss:Type="String">001</Data>'));
    expect(excel, contains('<Data ss:Type="String">  +CMD</Data>'));
    expect(excel, isNot(contains('ss:Formula')));
  });
}
