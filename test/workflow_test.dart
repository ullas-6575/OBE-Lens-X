import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/app.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/screens/image_source_screen.dart';
import 'package:my_app/services/auth_service.dart';
import 'package:my_app/services/ocr_service.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/report_export.dart';
import 'package:my_app/workflow/report_page.dart';
import 'package:my_app/workflow/scan_pages.dart';
import 'support/workflow_fakes.dart';

class FakeExporter implements ReportExporter {
  int calls = 0;
  @override
  Future<void> export(
      BuildContext context, String title, List<List<String>> rows,
      {required bool pdf}) async {
    calls++;
  }
}

void main() {
  testWidgets(
      'Restored teacher session traverses course, offering, exam, student and scanner',
      (tester) async {
    final repository = seededRepository();
    const ocr = MockOcrService(stepDuration: Duration.zero);
    await tester.pumpWidget(MarkSheetApp(
        authService: FakeAuthService(hasSession: true),
        workflowRepository: repository,
        ocrService: ocr));
    await tester.pumpAndSettle();
    for (final text in [
      'Assigned courses',
      'CSE3200 · Software Engineering',
      '2026 · Term 1',
      'Final',
      'Student / script details'
    ]) {
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byType(TextFormField), 'ROLL001');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Student ROLL001'), findsOneWidget);
    await tester.tap(find.text('Choose group and scan'));
    await tester.pumpAndSettle();
    final source =
        tester.widget<ImageSourceScreen>(find.byType(ImageSourceScreen));
    expect(source.ocrService, same(ocr));
    expect(source.workflow!.rollNo, 'ROLL001');
    expect(source.workflow!.groups, ['1-4']);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Student ROLL001'), findsOneWidget);
  });
  testWidgets('Pending teacher cannot enter scanner or assigned courses',
      (tester) async {
    await tester.pumpWidget(MarkSheetApp(
        authService: FakeAuthService(hasSession: true),
        workflowRepository: FakeWorkflowRepository()..approved = false));
    await tester.pumpAndSettle();
    expect(find.text('Your account is awaiting teacher approval.'),
        findsOneWidget);
    expect(find.text('Quick scan'), findsNothing);
    expect(find.text('Assigned courses'), findsNothing);
  });
  testWidgets('Admin dashboard exposes course, teacher and program journeys',
      (tester) async {
    await tester.pumpWidget(MarkSheetApp(
        authService: FakeAuthService(hasSession: true, isAdmin: true),
        workflowRepository: seededRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Admin dashboard'), findsOneWidget);
    expect(find.text('Manage courses'), findsOneWidget);
    expect(find.text('Manage teachers'), findsOneWidget);
    expect(find.text('Program reports'), findsOneWidget);
  });
  testWidgets('Session loss disposes protected navigation stack',
      (tester) async {
    final auth = FakeAuthService(hasSession: true);
    await tester.pumpWidget(MarkSheetApp(
        authService: auth, workflowRepository: seededRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assigned courses'));
    await tester.pumpAndSettle();
    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('CSE3200 · Software Engineering'), findsNothing);
  });
  testWidgets('Password recovery opens new-password page and returns to login',
      (tester) async {
    final auth = FakeAuthService(hasSession: true);
    await tester.pumpWidget(MarkSheetApp(
        authService: auth, workflowRepository: seededRepository()));
    await tester.pumpAndSettle();
    auth.events.add(SessionEvent.recovery);
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'new-password');
    await tester.enterText(find.byType(TextField).at(1), 'new-password');
    await tester.tap(find.text('Save password and return to login'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });
  testWidgets(
      'Failed summary save retains marks and retries the same submission',
      (tester) async {
    final repo = seededRepository()..failSave = true;
    final data = MarksTableData.empty(tableType: '1-4');
    data.cellMarks['1']!['a'] = '5';
    await tester.pumpWidget(MaterialApp(
        home: SubmissionPage(
            repository: repo,
            scan: const ScanContext(
                sampleCourse, sampleOffering, sampleExam, 'ROLL001'),
            data: data)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save result'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your reviewed marks are still here'),
        findsOneWidget);
    repo.failSave = false;
    await tester.tap(find.text('Retry save'));
    await tester.pumpAndSettle();
    expect(repo.submissions.length, 2);
    expect(repo.submissions[0], repo.submissions[1]);
    expect(find.text('Result saved'), findsOneWidget);
    expect(repo.resultRows.single['roll_no'], 'ROLL001');
  });
  testWidgets(
      'Stale report refreshes before export; unchanged report can export',
      (tester) async {
    final repo = seededRepository();
    final data = MarksTableData.empty(tableType: '1-4');
    data.cellMarks['1']!['a'] = '5';
    repo.resultRows.add({
      'id': 'r',
      'exam_id': 'exam',
      'roll_no': '1',
      'table_type': '1-4',
      'marks': data.cellMarks,
      'revision': 1
    });
    final exporter = FakeExporter();
    await tester.pumpWidget(MaterialApp(
        home: ReportPage(
            repository: repo,
            course: sampleCourse,
            offering: sampleOffering,
            exam: sampleExam,
            exporter: exporter)));
    await tester.pumpAndSettle();
    repo.resultRows.single['revision'] = 2;
    data.cellMarks['1']!['a'] = '8';
    await tester.scrollUntilVisible(find.text('Export PDF'), 300);
    await tester.tap(find.text('Export PDF'));
    await tester.pumpAndSettle();
    expect(exporter.calls, 0);
    expect(find.textContaining('Marks or mappings changed.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Export PDF'), 300);
    await tester.tap(find.text('Export PDF'));
    await tester.pumpAndSettle();
    expect(exporter.calls, 1);
  });
}
