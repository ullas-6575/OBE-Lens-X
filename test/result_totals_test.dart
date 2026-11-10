import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/workflow/grading.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/scan_pages.dart';
import 'package:my_app/widgets/marks_grid_table.dart';
import 'support/workflow_fakes.dart';

void main() {
  const course =
      Course(id: 'course', code: 'CSE3200', title: 'Software Engineering');
  const offering = Offering('offering', 'course', '2026', 'Term 1');
  const exam =
      Exam(id: 'exam', offeringId: 'offering', name: 'Final', questions: [
    QuestionMapping('1', 'a', 'CO1', 10),
    QuestionMapping('5', 'a', 'CO1', 10),
  ]);

  Map<String, Map<String, String>> marksFor(String question, String earned) => {
        question: {for (final part in MarksTableData.parts) part: 'N/A'}
          ..['a'] = earned,
      };

  testWidgets('Marks grid calculates each question and group total',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarksGridTable(marks: {
      ...marksFor('1', '6'),
      ...marksFor('2', '3'),
    }, showTotals: true))));

    expect(find.text('Total'), findsNWidgets(2));
    final questionOne = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('question-total-1')),
        matching: find.byType(Text)));
    final groupTotal = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('grid-grand-total')),
        matching: find.byType(Text)));
    expect(questionOne.data, '6');
    expect(groupTotal.data, '9');
  });

  testWidgets('Result details merge groups and calculate UGC GPA',
      (tester) async {
    final firstGroup = marksFor('1', '8');
    final secondGroup = marksFor('5', '8');
    await tester.pumpWidget(MaterialApp(
        home: StudentResultPage(
            repository: FakeWorkflowRepository(),
            scan: const ScanContext(course, offering, exam, 'ROLL001'),
            results: [
          {
            'table_type': '1-4',
            'revision': 1,
            'grand_total': 8,
            'marks': firstGroup,
          },
          {
            'table_type': '5-8',
            'revision': 1,
            'grand_total': 8,
            'marks': secondGroup,
          },
        ])));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('16 / 20'), 200,
        scrollable: find.byType(Scrollable).first);

    expect(find.text('16 / 20'), findsOneWidget);
    expect(find.text('80.00%'), findsOneWidget);
    expect(find.text('4.00'), findsOneWidget);
    expect(find.text('Group total: 8 / 10'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('GPA waits until every required group is saved', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: StudentResultPage(
            repository: FakeWorkflowRepository(),
            scan: const ScanContext(course, offering, exam, 'ROLL001'),
            results: [
          {
            'table_type': '1-4',
            'revision': 1,
            'grand_total': 8,
            'marks': marksFor('1', '8'),
          },
        ])));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Pending required groups'), 200,
        scrollable: find.byType(Scrollable).first);

    expect(find.text('Pending required groups'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  test('UGC 4.0 grade-point boundaries', () {
    expect(bangladeshUgcGradePoint(80), 4.0);
    expect(bangladeshUgcGradePoint(79.99), 3.75);
    expect(bangladeshUgcGradePoint(75), 3.75);
    expect(bangladeshUgcGradePoint(40), 2.0);
    expect(bangladeshUgcGradePoint(39.99), 0);
  });
}
