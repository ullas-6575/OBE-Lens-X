import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/screens/image_source_screen.dart';
import 'package:my_app/screens/verification_screen.dart';
import 'package:my_app/services/ocr_service.dart';
import 'package:my_app/workflow/exam_pages.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/scan_pages.dart';

import 'support/workflow_fakes.dart';

const twoPartExam =
    Exam(id: 'exam', offeringId: 'offering', name: 'Final', questions: [
  QuestionMapping('1', 'a', 'CO1', 10),
  QuestionMapping('5', 'a', 'CO1', 10),
]);

class ScanRepository extends FakeWorkflowRepository {
  int resultLoads = 0;

  @override
  Future<List<Json>> results(String examId) {
    resultLoads++;
    return super.results(examId);
  }
}

MarksTableData part(String group) {
  final data = MarksTableData.empty(tableType: group);
  data.cellMarks[group == '1-4' ? '1' : '5']!['a'] = '7';
  return data;
}

Future<void> press(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> startScan(WidgetTester tester, ScanRepository repo,
    {Exam exam = twoPartExam}) async {
  await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: ExamPage(
          repository: repo,
          course: sampleCourse,
          offering: sampleOffering,
          exam: exam,
          ocrService: const MockOcrService(stepDuration: Duration.zero))));
  await tester.pumpAndSettle();
  await press(tester, 'Scan');
  await tester.enterText(find.byType(TextFormField), 'ROLL001');
  await press(tester, 'Continue');
  expect(find.byType(ImageSourceScreen), findsOneWidget);
}

Future<void> reviewPart(WidgetTester tester, MarksTableData data) async {
  final source =
      tester.widget<ImageSourceScreen>(find.byType(ImageSourceScreen));
  Navigator.of(tester.element(find.byType(ImageSourceScreen))).push(
      MaterialPageRoute<void>(
          builder: (_) => VerificationScreen(
              marksTableData: data,
              imagePath: 'test/fixtures/exif_orientation_6.jpg',
              workflow: source.workflow)));
  await tester.pumpAndSettle();
  await press(tester, 'Verify & Submit');
}

void main() {
  testWidgets('Done after one part returns to the exam and asks for a new roll',
      (tester) async {
    final repo = ScanRepository();
    await startScan(tester, repo);
    await reviewPart(tester, part('1-4'));
    expect(find.text('Part complete'), findsOneWidget);
    expect(find.text('Scan other part'), findsOneWidget);
    expect(repo.resultRows.single['roll_no'], 'ROLL001');
    await press(tester, 'Done');
    expect(find.byType(ExamPage), findsOneWidget);
    expect(find.byType(StudentScanPage), findsNothing);
    expect(find.byType(VerificationScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(repo.resultLoads, 1);
    await press(tester, 'Scan');
    expect(find.text('Student / script details'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final first in ['1-4', '5-8']) {
    testWidgets('Scanning $first then the other part finishes on the exam page',
        (tester) async {
      final repo = ScanRepository();
      await startScan(tester, repo);
      await reviewPart(tester, part(first));
      await press(tester, 'Scan other part');
      final other = first == '1-4' ? '5-8' : '1-4';
      final source =
          tester.widget<ImageSourceScreen>(find.byType(ImageSourceScreen));
      expect(source.workflow!.groups, [other]);
      expect(source.workflow!.rollNo, 'ROLL001');
      expect(
          tester
              .widget<SegmentedButton<String>>(
                  find.byType(SegmentedButton<String>))
              .selected,
          {other});
      expect(find.byType(VerificationScreen), findsNothing);
      await reviewPart(tester, part(other));
      expect(find.text('Part complete'), findsOneWidget);
      expect(find.text('Scan other part'), findsNothing);
      expect(repo.resultRows.length, 2);
      expect(repo.resultRows.map((row) => row['roll_no']),
          everyElement('ROLL001'));
      await press(tester, 'Done');
      expect(find.byType(ExamPage), findsOneWidget);
      expect(find.byType(StudentScanPage), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(repo.resultLoads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'A failed save keeps the reviewed part and only finishes on retry',
      (tester) async {
    final repo = ScanRepository()..failSave = true;
    await startScan(tester, repo);
    await reviewPart(tester, part('1-4'));
    expect(find.text('Part complete'), findsNothing);
    expect(find.textContaining('Your reviewed marks are still here'),
        findsOneWidget);
    expect(repo.resultRows, isEmpty);
    repo.failSave = false;
    await press(tester, 'Retry save');
    expect(find.text('Part complete'), findsOneWidget);
    expect(repo.resultRows.single['marks']['1']['a'], '7');
    expect(repo.submissions.length, 2);
    expect(repo.submissions.first, repo.submissions.last);
    await press(tester, 'Done');
    expect(find.byType(ExamPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Four answered questions still need a choice before saving',
      (tester) async {
    final repo = ScanRepository();
    final exam = Exam(
        id: 'exam',
        offeringId: 'offering',
        name: 'Final',
        requiredGroups: [
          '1-4'
        ],
        questions: [
          for (var q = 1; q <= 4; q++) QuestionMapping('$q', 'a', 'CO1', 10),
        ]);
    final data = MarksTableData.empty(tableType: '1-4');
    for (var q = 1; q <= 4; q++) {
      data.cellMarks['$q']!['a'] = '$q';
    }
    await startScan(tester, repo, exam: exam);
    await reviewPart(tester, data);
    expect(find.byType(SubmissionPage), findsOneWidget);
    expect(repo.submissions, isEmpty);
    for (var q = 1; q <= 3; q++) {
      await press(tester, 'Count Q$q');
    }
    await press(tester, 'Save result');
    expect(find.text('Part complete'), findsOneWidget);
    expect(find.text('Scan other part'), findsNothing);
    expect(repo.resultRows.single['selected_questions'], ['1', '2', '3']);
    expect(repo.resultRows.single['grand_total'], 6);
    expect(repo.resultRows.single['marks']['4']['a'], '4');
    await press(tester, 'Done');
    expect(find.byType(ExamPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final replace in [false, true]) {
    testWidgets(
        'Finishing a duplicate part can ${replace ? 'replace' : 'keep'} marks',
        (tester) async {
      final repo = ScanRepository();
      await repo.saveMarks(
          const ScanContext(
              sampleCourse, sampleOffering, twoPartExam, 'ROLL001'),
          'original',
          '1-4',
          part('1-4').cellMarks);
      final replacement = part('1-4');
      replacement.cellMarks['1']!['a'] = '9';
      await startScan(tester, repo);
      await reviewPart(tester, replacement);
      expect(find.text('Replace previous marks?'), findsOneWidget);
      expect(find.text('Part complete'), findsNothing);
      await press(tester, replace ? 'Replace marks' : 'Keep previous');
      expect(find.text('Part complete'), findsOneWidget);
      expect(repo.resultRows.single['marks']['1']['a'], replace ? '9' : '7');
      await press(tester, 'Done');
      expect(find.byType(ExamPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Cancelling the other part offers retry without a loading screen',
      (tester) async {
    final repo = ScanRepository();
    await startScan(tester, repo);
    await reviewPart(tester, part('1-4'));
    await press(tester, 'Scan other part');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Scan cancelled. Tap Scan to try again.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await press(tester, 'Scan');
    expect(
        tester
            .widget<ImageSourceScreen>(find.byType(ImageSourceScreen))
            .workflow!
            .groups,
        ['5-8', '1-4']);
    expect(repo.resultRows.length, 1);
    expect(tester.takeException(), isNull);
  });
}
