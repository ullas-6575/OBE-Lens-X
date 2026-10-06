import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/screens/verification_screen.dart';

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

void main() {
  testWidgets(
      'Whole table submits without opening flagged cells; no confidence ticks',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: VerificationScreen(marksTableData: predictions())));
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
    await tester.tap(find.text('Verify & Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Marks Verified & Computed!'), findsOneWidget);
    expect(find.text('Edit Mark'), findsNothing);
    expect(find.text('25'), findsWidgets);
  });

  testWidgets('Optional Edit Mark dialog saves changes and respects maximum',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: VerificationScreen(marksTableData: predictions())));
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
    await tester.tap(find.text('Verify & Submit'));
    await tester.pumpAndSettle();
    expect(find.text('Marks Verified & Computed!'), findsOneWidget);
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
    expect(lowConfidenceNumber.needsAttention, isFalse);
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
