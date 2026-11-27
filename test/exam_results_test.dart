import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/widgets/worksheet_grid.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/results_excel_export.dart';
import 'package:my_app/workflow/scan_pages.dart';
import 'support/workflow_fakes.dart';

const exam =
    Exam(id: 'exam', offeringId: 'offering', name: 'Final', questions: [
  QuestionMapping('5', 'a', 'CO2', 10),
  QuestionMapping('1', 'b', 'CO1', 10),
  QuestionMapping('1', 'a', 'CO1', 10),
]);

Json result(String examId, String roll, String group,
        Map<String, Map<String, String>> marks) =>
    {
      'exam_id': examId,
      'roll_no': roll,
      'table_type': group,
      'marks': marks,
      'revision': 1,
    };

void main() {
  test('Worksheet merges groups, orders parts and excludes other exams', () {
    final results = [
      result('exam', '10', '1-4', {
        '1': {'a': '04', 'b': '8'},
      }),
      result('other-exam', 'unrelated', '1-4', {
        '1': {'a': '9'},
      }),
      result('exam', '2', '5-8', {
        '5': {'a': '7'},
      }),
      result('exam', '2', '1-4', {
        '1': {'a': '10', 'b': 'N/A'},
      }),
    ];
    expect(resultsWorksheet(exam, results), [
      ['Roll', '1a', '1b', '5a'],
      ['2', '10', 'N/A', '7'],
      ['10', '04', '8', 'N/A'],
    ]);
    final excel = resultsExcelXml(exam, results);
    expect(excel, contains('<Data ss:Type="String">04</Data>'));
    expect(excel, isNot(contains('unrelated')));
  });

  testWidgets('All results shows a course worksheet and opens student details',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = seededRepository()
      ..resultRows.addAll([
        result('exam', '98', '1-4', {
          '1': {'a': '10', 'b': 'N/A'},
        }),
        result('exam', '98', '5-8', {
          '5': {'a': '04'},
        }),
        result('other-exam', 'other-student', '1-4', {
          '1': {'a': '9'},
        }),
      ]);
    await tester.pumpWidget(MaterialApp(
        home: ExamResultsPage(
            repository: repo,
            course: sampleCourse,
            offering: sampleOffering,
            exam: exam)));
    await tester.pumpAndSettle();
    expect(find.text('Calculate attainment'), findsNothing);
    expect(find.text('CSE3200 · 2026 · Term 1'), findsOneWidget);
    expect(find.text('Roll'), findsOneWidget);
    expect(find.text('98'), findsOneWidget);
    expect(find.text('1a'), findsOneWidget);
    expect(find.text('5a'), findsOneWidget);
    expect(find.text('other-student'), findsNothing);
    expect(tester.widget<WorksheetGrid>(find.byType(WorksheetGrid)).rows, [
      ['Roll', '1a', '1b', '5a'],
      ['98', '10', 'N/A', '04'],
    ]);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('98'));
    await tester.pumpAndSettle();
    expect(find.text('Result details · 98'), findsOneWidget);
    expect(
        tester
            .widget<StudentResultPage>(find.byType(StudentResultPage))
            .results
            .length,
        2);
    await tester.pageBack();
    await tester.pumpAndSettle();

    const otherCourse = Course(id: 'other', code: 'CSE3201', title: 'Other');
    const otherOffering = Offering('other', 'other', '2026', 'Term 1');
    const otherExam = Exam(
        id: 'other-exam',
        offeringId: 'other',
        name: 'Final',
        requiredGroups: ['1-4'],
        questions: [QuestionMapping('1', 'a', 'CO1', 10)]);
    await tester.pumpWidget(MaterialApp(
        home: ExamResultsPage(
            repository: repo,
            course: otherCourse,
            offering: otherOffering,
            exam: otherExam)));
    await tester.pumpAndSettle();
    expect(find.text('CSE3201 · 2026 · Term 1'), findsOneWidget);
    expect(find.text('other-student'), findsOneWidget);
    expect(find.text('98'), findsNothing);
  });

  testWidgets('Empty course results disable Excel export', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ExamResultsPage(
            repository: seededRepository(),
            course: sampleCourse,
            offering: sampleOffering,
            exam: sampleExam)));
    await tester.pumpAndSettle();
    expect(find.text('No saved results for this exam.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byWidgetPredicate((widget) => widget is FilledButton))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  test('Worksheet supports Excel column letters beyond Z', () {
    expect([0, 25, 26, 51, 52, 702].map(worksheetColumnName),
        ['A', 'Z', 'AA', 'AZ', 'BA', 'AAA']);
  });
}
