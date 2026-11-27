import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/report_export.dart';
import 'package:my_app/workflow/report_page.dart';
import 'support/workflow_fakes.dart';

class _NoopExporter implements ReportExporter {
  @override
  Future<void> export(
      BuildContext context, String title, List<List<String>> rows) async {}
}

void main() {
  testWidgets('Program PO contributions are sorted across courses',
      (tester) async {
    final repo = FakeWorkflowRepository();
    for (final entry in {
      'CSE3200': ['PO10', 'PO2'],
      'CSE3201': ['PO12', 'PO1'],
    }.entries) {
      repo.courseRows.add(Course(
          id: entry.key,
          code: entry.key,
          title: 'Course',
          outcomes: [CourseOutcome('CO1', 'CO1', entry.value)]));
      repo.offeringRows.add(Offering(entry.key, entry.key, '2026', 'Term 1'));
      repo.examRows.add(Exam(
          id: entry.key,
          offeringId: entry.key,
          name: 'Final',
          requiredGroups: sampleExam.requiredGroups,
          questions: sampleExam.questions));
      repo.resultRows.add({
        'exam_id': entry.key,
        'roll_no': '1',
        'table_type': '1-4',
        'marks': MarksTableData.empty(tableType: '1-4').cellMarks
          ..['1']!['a'] = '5',
      });
    }
    await tester
        .pumpWidget(MaterialApp(home: ProgramReportPage(repository: repo)));
    await tester.enterText(find.byType(TextField).at(0), '2026');
    await tester.enterText(find.byType(TextField).at(1), 'Term 1');
    await tester.tap(find.text('Calculate program aggregation'));
    await tester.pumpAndSettle();

    final preview = tester.widget<ReportPreview>(find.byType(ReportPreview));
    final rows = preview.report.rows;
    final header = rows.indexWhere((row) => row.first == 'PO');
    expect(rows.skip(header + 1).take(4).map((row) => row.first),
        ['PO1', 'PO2', 'PO10', 'PO12']);
    expect(rows.where((row) => row.first == 'CSE3200').map((row) => row[1]),
        ['PO2', 'PO10']);
    expect(preview.report.exportable, isTrue);
    final workbook = reportExcelXml(rows);
    expect(RegExp('<Worksheet ').allMatches(workbook).length, 3);
    expect(workbook, contains('<Worksheet ss:Name="Report details">'));
    expect(workbook, contains('<Worksheet ss:Name="PO contributions">'));
    expect(workbook, contains('<Worksheet ss:Name="Course breakdown">'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Report preview renders worksheet grids on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const report = ReportSnapshot(
        'fingerprint',
        'CSE3200 - Final',
        [
          ['Course', 'CSE3200 Software Engineering'],
          ['Offering', '2026 · Term 1'],
          ['Roll no', 'CO1', 'CO2', 'CO3', 'CO4'],
          ['2026001', '1', '0', '1', '0'],
          ['2026002', 'N/A', 'N/A', 'N/A', 'N/A'],
          ['CO', 'Eligible', 'Attained', 'Attainment %', 'Level'],
          ['CO1', '1', '1', '100.00', 'L4'],
          ['Course PO contribution', 'Equal mean of linked CO percentages'],
          ['PO', 'Contribution %', 'Level'],
          ['PO1', '100.00', 'L4'],
          ['Scope', 'Course contribution only.'],
        ],
        [],
        true);

    await tester.pumpWidget(MaterialApp(
        home: SingleChildScrollView(
            child: ReportPreview(
                report: report,
                load: () async => report,
                onStale: () {},
                exporter: _NoopExporter()))));
    await tester.pumpAndSettle();

    expect(find.text('CSE3200 - Final'), findsOneWidget);
    expect(find.text('COURSE OUTCOME ATTAINMENT'), findsOneWidget);
    expect(find.text('STUDENT CO ATTAINMENT'), findsOneWidget);
    expect(find.text('Roll no'), findsOneWidget);
    expect(find.text('2026001'), findsOneWidget);
    expect(find.text('2026002'), findsOneWidget);
    expect(find.text('Status'), findsNothing);
    expect(find.text('Course'), findsOneWidget);
    expect(find.text('Eligible'), findsOneWidget);
    expect(find.text('CO1'), findsNWidgets(2));
    expect(find.text('CO4'), findsOneWidget);
    expect(find.text('L4'), findsNWidgets(2));
    expect(find.text('COURSE PO CONTRIBUTION'), findsOneWidget);
    expect(find.text('PO1'), findsOneWidget);
    expect(find.text('fx'), findsNothing);
    expect(find.text('Scope'), findsNothing);
    expect(find.text('Export to Excel'), findsOneWidget);
    expect(find.text('Export PDF'), findsNothing);
    expect(find.text('Export spreadsheet (CSV)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
