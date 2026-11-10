import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/workflow/report_export.dart';
import 'package:my_app/workflow/report_page.dart';

class _NoopExporter implements ReportExporter {
  @override
  Future<void> export(
      BuildContext context, String title, List<List<String>> rows,
      {required bool pdf}) async {}
}

void main() {
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
          ['CO', 'Eligible', 'Attained', 'Attainment %', 'Target met'],
          ['CO1', '1', '1', '100.00', 'Yes'],
          ['Course PO contribution', 'Equal mean of linked CO percentages'],
          ['PO1', '100.00'],
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
    expect(find.text('Eligible'), findsOneWidget);
    expect(find.text('CO1'), findsOneWidget);
    expect(find.text('COURSE PO CONTRIBUTION'), findsOneWidget);
    expect(find.text('PO1'), findsOneWidget);
    await tester.tap(find.text('CO1'));
    await tester.pumpAndSettle();
    expect(find.text('CO ATTAINMENT!B3'), findsOneWidget);
    expect(find.text('CO1'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
