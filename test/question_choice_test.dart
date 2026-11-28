import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/workflow/attainment.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/results_excel_export.dart';
import 'package:my_app/workflow/scan_pages.dart';
import 'support/workflow_fakes.dart';

const course =
    Course(id: 'course', code: 'CSE3200', title: 'Course', outcomes: [
  CourseOutcome('CO1', 'First', ['PO1']),
  CourseOutcome('CO2', 'Optional', ['PO1']),
]);
const exam = Exam(
    id: 'exam',
    offeringId: 'offering',
    name: 'Three of four',
    requiredGroups: [
      '1-4'
    ],
    questions: [
      QuestionMapping('1', 'a', 'CO1', 10),
      QuestionMapping('2', 'a', 'CO1', 10),
      QuestionMapping('3', 'a', 'CO1', 10),
      QuestionMapping('4', 'a', 'CO2', 10),
    ]);
const scan = ScanContext(course, sampleOffering, exam, 'ROLL001');

MarksTableData data(List<String> values) {
  final table = MarksTableData.empty(tableType: '1-4');
  for (var i = 0; i < 4; i++) {
    table.cellMarks['${i + 1}']!['a'] = values[i];
  }
  return table;
}

Json row(List<String> values, [List<String>? selected]) => {
      'id': 'result',
      'exam_id': 'exam',
      'roll_no': 'ROLL001',
      'table_type': '1-4',
      'revision': 1,
      'marks': data(values).cellMarks,
      if (selected != null) 'selected_questions': selected,
    };

void main() {
  test('Three answered questions are automatic; numeric zero is an answer', () {
    final result = row(['0', '5', 'N/A', '8']);
    expect(
        exam.countedQuestions('1-4', null, result['marks']), ['1', '2', '4']);
    expect(exam.countedTotal(result), 13);
    expect(exam.countedMaximum(result), 30);
  });
  test('Missing answers score zero against three-question maximum', () {
    expect(exam.countedTotal(row(['8', 'N/A', 'N/A', '7'])), 15);
    expect(exam.countedMaximum(row(['8', 'N/A', 'N/A', '7'])), 30);
    expect(exam.countedTotal(row(['N/A', 'N/A', 'N/A', 'N/A'])), 0);
    expect(exam.countedMaximum(row(['N/A', 'N/A', 'N/A', 'N/A'])), 30);
  });
  test('Missing slots use the largest remaining maxima when questions differ',
      () {
    const unequal = Exam(
        id: 'unequal',
        offeringId: 'offering',
        name: 'Unequal',
        requiredGroups: [
          '1-4'
        ],
        questions: [
          QuestionMapping('1', 'a', 'CO1', 2),
          QuestionMapping('2', 'a', 'CO1', 4),
          QuestionMapping('3', 'a', 'CO1', 6),
          QuestionMapping('4', 'a', 'CO1', 8),
        ]);
    final result = row(['1', 'N/A', 'N/A', 'N/A']);
    expect(unequal.countedTotal(result), 1);
    expect(unequal.countedMaximum(result), 16);
  });
  test(
      'Four answered questions require an explicit choice, not the highest three',
      () {
    expect(exam.countedTotal(row(['1', '2', '3', '9'])), isNull);
    expect(exam.countedTotal(row(['1', '2', '3', '9'], ['1', '2', '3'])), 6);
    expect(exam.countedMaximum(row(['1', '2', '3', '9'], ['1', '2', '3'])), 30);
    expect(exam.countedTotal(row(['1', '2', '3', '9'], ['1', '2', '3', '4'])),
        isNull);
    expect(
        exam.countedTotal(row(['1', '2', '3', '9'], ['1', '1', '2'])), isNull);
    expect(exam.countedTotal(row(['1', '2', 'N/A', '9'], ['1', '2', '3'])), 12);
  });
  test('CO and PO calculations exclude the uncounted fourth question', () {
    final report = const AttainmentCalculator().calculate(course, exam, [
      row(['5', '5', '5', '10'], ['1', '2', '3'])
    ]);
    expect(report.exportable, isTrue);
    expect(report.studentRows.single.outcomes, {'CO1': 1});
    expect(report.outcomes.map((score) => score.percent), [100, null]);
    expect(report.poContribution['PO1'], 100);
    final pending = const AttainmentCalculator().calculate(course, exam, [
      row(['5', '5', '5', '10'])
    ]);
    expect(pending.exportable, isFalse);
  });
  test('Worksheet preserves raw marks and shows only obtained and total marks',
      () {
    final sheet = resultsWorksheet(exam, [
      row(['1', '2', '3', '9'], ['1', '2', '3'])
    ]);
    expect(sheet.first, [
      'Roll',
      '1a',
      '2a',
      '3a',
      '4a',
      'Total Obtained Marks',
      'Total Marks'
    ]);
    expect(sheet[1], ['ROLL001', '1', '2', '3', '9', '6', '30']);
    final excel = resultsExcelXml(exam, [
      row(['1', '2', '3', '9'], ['1', '2', '3'])
    ]);
    expect(excel, contains('Total Obtained Marks'));
    expect(excel, contains('Total Marks'));
    expect(excel, isNot(contains('Counted Q')));
    expect(excel, isNot(contains('Q1, Q2, Q3')));
  });

  test('Worksheet totals stay pending until counted questions are selected',
      () {
    final sheet = resultsWorksheet(exam, [
      row(['1', '2', '3', '9'])
    ]);
    expect(sheet[1], ['ROLL001', '1', '2', '3', '9', 'Pending', 'Pending']);
  });

  for (final answered in [2, 3, 4]) {
    testWidgets('Ask for selection only when $answered questions are answered',
        (tester) async {
      final repo = seededRepository();
      final values = [
        '1',
        '2',
        answered >= 3 ? '3' : 'N/A',
        answered == 4 ? '9' : 'N/A'
      ];
      await tester.pumpWidget(MaterialApp(
          home: SubmissionPage(
              repository: repo, scan: scan, data: data(values))));
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip),
          answered == 4 ? findsNWidgets(4) : findsNothing);
      if (answered == 4) {
        expect(
            tester
                .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Save result'))
                .onPressed,
            isNull);
        for (final q in ['1', '2', '3']) {
          await tester.ensureVisible(find.text('Count Q$q'));
          await tester.tap(find.text('Count Q$q'));
          await tester.pumpAndSettle();
        }
      }
      await tester.ensureVisible(find.text('Save result'));
      await tester.tap(find.text('Save result'));
      await tester.pumpAndSettle();
      expect(find.text('Result saved'), findsOneWidget);
      expect(repo.resultRows.single['selected_questions'],
          answered == 2 ? ['1', '2'] : ['1', '2', '3']);
      expect(repo.resultRows.single['grand_total'], answered == 2 ? 3 : 6);
      expect((repo.resultRows.single['marks'] as Map)['4']['a'],
          answered == 4 ? '9' : 'N/A');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Result GPA uses three-question maximum including missing zeroes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: StudentResultPage(
            repository: seededRepository(),
            scan: scan,
            results: [
          row(['8', 'N/A', 'N/A', '7'])
        ])));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('15 / 30'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('50.00%'), findsOneWidget);
    expect(find.text('2.50'), findsOneWidget);
    expect(find.text('Choose counted questions'), findsNothing);
  });
  testWidgets(
      'Merged GPA counts three questions from each group, not all eight',
      (tester) async {
    final both = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Both groups',
        questions: [
          ...exam.questions,
          for (var q = 5; q <= 8; q++) QuestionMapping('$q', 'a', 'CO1', 10),
        ]);
    final second = MarksTableData.empty(tableType: '5-8');
    for (var q = 5; q <= 8; q++) {
      second.cellMarks['$q']!['a'] = q == 8 ? '10' : '${q - 1}';
    }
    await tester.pumpWidget(MaterialApp(
        home: StudentResultPage(
            repository: seededRepository(),
            scan: ScanContext(course, sampleOffering, both, 'ROLL001'),
            results: [
          row(['1', '2', '3', '9'], ['1', '2', '3']),
          {
            'table_type': '5-8',
            'revision': 1,
            'marks': second.cellMarks,
            'selected_questions': const ['5', '6', '7']
          },
        ])));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('21 / 60'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('35.00%'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
  });
}
