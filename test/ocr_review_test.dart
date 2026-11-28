import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/models/scan_workflow.dart';
import 'package:my_app/screens/verification_screen.dart';
import 'package:my_app/services/result_service.dart';

MarksTableData predictions() => MarksTableData.empty(tableType: '1-4').copyWith(
      cellMarks: {
        '1': {'a': '15', 'b': '10', 'c': 'o7', 'd': 'N/A'}
      },
      cellResults: {
        '1': {
          'a': const CellOcrResult(
              text: '15', confidence: .4, needsReview: true, maxMark: 20),
          'b': const CellOcrResult(
              text: '10', confidence: .99, needsReview: false),
          'c': const CellOcrResult(
              text: 'o7',
              confidence: .5,
              needsReview: false,
              reason: 'expected_one_or_two_digits'),
          'd': const CellOcrResult(
              text: '', confidence: 0, needsReview: true, reason: 'empty_cell'),
        }
      },
    );

class _FakeResultService implements ResultService {
  final List<String> submissions = [];
  Completer<void>? pending;

  @override
  Future<List<Map<String, dynamic>>> fetchResults() async => const [];

  @override
  Future<void> saveResult({
    required String rollNo,
    required String submissionId,
    required String tableType,
    required Map<String, Map<String, String>> marks,
    required double grandTotal,
  }) async {
    submissions.add(submissionId);
    await pending?.future;
  }
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets(
        'Verification rows g and Total align with question columns at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          home: VerificationScreen(
              marksTableData: MarksTableData.empty(tableType: '1-4'))));
      await tester.pumpAndSettle();
      for (final q in MarksTableData.type1Questions) {
        final header = tester.getRect(find.byKey(ValueKey('heading-$q')));
        for (final key in ['mark-$q-a', 'mark-$q-g', 'total-$q']) {
          final cell = tester.getRect(find.byKey(ValueKey(key)));
          expect(cell.left, closeTo(header.left, .1));
          expect(cell.right, closeTo(header.right, .1));
        }
      }
      expect(find.text('Grand\nTotal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Exam maximum highlights confident OCR until corrected',
      (tester) async {
    final reviewed = <MarksTableData>[];
    final data = MarksTableData.empty(tableType: '1-4').copyWith(cellMarks: {
      '1': {'a': '15'}
    }, cellResults: {
      '1': {
        'a': const CellOcrResult(
            text: '15',
            confidence: .99,
            needsReview: false,
            teacherReviewed: true,
            maxMark: 20)
      }
    });
    final workflow = ScanWorkflow(
        rollNo: 'ROLL001',
        description: 'Final',
        groups: const ['1-4'],
        maximumFor: (_, __) => 10,
        validate: (_, __) => null,
        review: (data) async {
          reviewed.add(data);
        });
    await tester.pumpWidget(MaterialApp(
        home: VerificationScreen(marksTableData: data, workflow: workflow)));
    await tester.pumpAndSettle();
    Color? color() => (tester
            .widget<Container>(find.byKey(const ValueKey('mark-1-a')))
            .decoration! as BoxDecoration)
        .color;
    expect(color(), Colors.red.shade100);
    await tester.tap(find.text('Verify & Submit'));
    await tester.pumpAndSettle();
    expect(reviewed, isEmpty);
    expect(find.textContaining('exceeds its maximum of 10'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('edit-1-a')));
    await tester.tap(find.byKey(const ValueKey('edit-1-a')));
    await tester.pumpAndSettle();
    expect(find.text('Maximum 10'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('edit-mark-input')), '11');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Exceeds the maximum mark.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('edit-mark-input')), '08');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(color(), isNull);
    await tester.tap(find.text('Verify & Submit'));
    await tester.pumpAndSettle();
    expect(reviewed.single.getMark('1', 'a'), '08');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manual marks update the maximum highlight while typing',
      (tester) async {
    final workflow = ScanWorkflow(
        rollNo: 'ROLL001',
        description: 'Final',
        groups: const ['1-4'],
        maximumFor: (_, __) => 10,
        validate: (_, __) => null,
        review: (_) async {});
    await tester.pumpWidget(MaterialApp(
        home: VerificationScreen(
            marksTableData: MarksTableData.empty(tableType: '1-4'),
            workflow: workflow)));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('manual-1-g'));
    Color? color() => (tester
            .widget<Container>(find.byKey(const ValueKey('mark-1-g')))
            .decoration! as BoxDecoration)
        .color;
    await tester.ensureVisible(field);
    await tester.enterText(field, '11');
    await tester.pump();
    expect(color(), Colors.red.shade100);
    await tester.enterText(field, '10');
    await tester.pump();
    expect(color(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manual entry rejects decimals instead of silently saving N/A',
      (tester) async {
    final service = _FakeResultService();
    await tester.pumpWidget(MaterialApp(
        home: VerificationScreen(
            marksTableData: MarksTableData.empty(), resultService: service)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'ROLL001');
    await tester.enterText(find.byKey(const ValueKey('manual-1-a')), '1.5');
    await tester.tap(find.text('Verify & Submit'));
    await tester.pump();

    expect(find.textContaining('must be an integer'), findsOneWidget);
    expect(service.submissions, isEmpty);
  });

  testWidgets('Failed saves retain the grid and retry with the same submission',
      (tester) async {
    final service = _FakeResultService()..pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: VerificationScreen(
            marksTableData: predictions(), resultService: service)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'ROLL001');
    await tester.tap(find.text('Verify & Submit'));
    await tester.pump();
    expect(service.submissions.length, 1);
    expect(
        tester
            .widget<FilledButton>(
                find.byWidgetPredicate((widget) => widget is FilledButton))
            .onPressed,
        isNull);
    expect(find.text('Marks Verified & Saved!'), findsNothing);

    service.pending!.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save result:'), findsOneWidget);
    expect(find.text('Marks Verified & Saved!'), findsNothing);
    expect(find.text('15'), findsWidgets);

    // The error snackbar temporarily overlays the bottom submit button.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    service.pending = null;
    await tester.tap(find.text('Verify & Submit'));
    await tester.pumpAndSettle();
    expect(service.submissions.length, 2);
    expect(service.submissions[0], service.submissions[1]);
    expect(find.text('Marks Verified & Saved!'), findsOneWidget);

    await tester.tap(find.text('View Saved Results'));
    await tester.pumpAndSettle();
    expect(find.text('No saved results found.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Whole table submits without opening flagged cells; no confidence ticks',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: VerificationScreen(
            marksTableData: predictions(),
            resultService: _FakeResultService())));
    await tester.pumpAndSettle();
    expect(find.text('15'), findsWidgets);
    expect(find.text('o7'), findsNothing);
    final confused = find.byKey(const ValueKey('edit-1-c'));
    expect(find.descendant(of: confused, matching: find.text('N/A')),
        findsOneWidget);
    expect(
        find.descendant(
            of: confused, matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget);
    final high = find.byKey(const ValueKey('edit-1-b'));
    expect(
        find.descendant(of: high, matching: find.byType(Icon)), findsNothing);
    final low = find.byKey(const ValueKey('edit-1-a'));
    expect(find.descendant(of: low, matching: find.byType(Icon)), findsNothing);
    final blank = find.byKey(const ValueKey('edit-1-d'));
    expect(
        find.descendant(of: blank, matching: find.byType(Icon)), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'ROLL001');
    await tester.tap(find.text('Verify & Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Marks Verified & Saved!'), findsOneWidget);
    expect(find.text('Edit Mark'), findsNothing);
    expect(find.text('25'), findsWidgets);
  });

  testWidgets('Optional Edit Mark dialog saves changes and respects maximum',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: VerificationScreen(
            marksTableData: predictions(),
            resultService: _FakeResultService())));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('edit-1-a'));
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('Edit Mark'), findsOneWidget);
    expect(find.text('OCR text: 15'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('edit-mark-input')), '25');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Exceeds the maximum mark.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('edit-mark-input')), '16');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('16'), findsWidgets);
    expect(
        find.descendant(of: cell, matching: find.byType(Icon)), findsNothing);
    // Another untouched flagged cell does not block whole-table submission.
    await tester.enterText(find.byType(TextFormField), 'ROLL001');
    await tester.tap(find.text('Verify & Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Marks Verified & Saved!'), findsOneWidget);
  });

  testWidgets(
      'Raw OCR stays in dialog; cancel retains warning and Set N/A clears it',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: VerificationScreen(marksTableData: predictions())));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('edit-1-c'));
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('OCR text: o7'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
                find.byKey(const ValueKey('edit-mark-input')))
            .controller!
            .text,
        isEmpty);
    await tester.enterText(find.byKey(const ValueKey('edit-mark-input')), 'o7');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter one or two digits, or set N/A.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('o7'), findsNothing);
    expect(
        find.descendant(
            of: cell, matching: find.byIcon(Icons.warning_amber_rounded)),
        findsOneWidget);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set N/A'));
    await tester.pumpAndSettle();
    expect(find.text('o7'), findsNothing);
    expect(
        find.descendant(of: cell, matching: find.text('N/A')), findsOneWidget);
    expect(
        find.descendant(of: cell, matching: find.byType(Icon)), findsNothing);
  });

  test(
      'Blank metadata overrides flags, but teacher-entered digits survive review',
      () {
    const blank =
        CellOcrResult(text: '', confidence: 0, needsReview: true, empty: true);
    expect(blank.needsAttention, isFalse);
    const lowConfidenceNumber = CellOcrResult(
        text: '15', confidence: .2, needsReview: true, maxMark: 10);
    expect(lowConfidenceNumber.needsAttention, isTrue);
    const withinMaximum = CellOcrResult(
        text: '10', confidence: .2, needsReview: true, maxMark: 10);
    expect(withinMaximum.needsAttention, isFalse);
    const rejectedText =
        CellOcrResult(text: 'o7', confidence: .99, needsReview: false);
    expect(rejectedText.needsAttention, isTrue);
    final data = MarksTableData.empty(tableType: '1-4').copyWith(cellMarks: {
      '1': {'a': '08'}
    }, cellResults: {
      '1': {'a': blank.reviewed()}
    });
    expect(data.getMark('1', 'a'), '08');
    for (final raw in ['o7', '?', 'NaN', 'Infinity', '-1', '1.5']) {
      expect(MarksTableData.normalizeMark(raw), 'N/A');
      expect(MarksTableData.parseMarkValue(raw), 0);
    }
    expect(MarksTableData.normalizeMark(' 07 '), '07');
  });
}
