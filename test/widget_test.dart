import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/main.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/screens/image_processing_screen.dart';
import 'package:my_app/screens/verification_screen.dart';

void main() {
  testWidgets(
      'Screen 1 has ONLY the 2 scan method buttons and table type selector',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MarkSheetApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'demo@obelens.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Lens2026!');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    // Verify Screen 1 title and header
    expect(find.text('MarkSheet OCR'), findsOneWidget);
    expect(find.text('Exam MarkSheet Scanner'), findsOneWidget);

    // Verify Table Type Selector has Q1-Q4 and Q5-Q8
    expect(find.text('Questions 1, 2, 3, 4'), findsOneWidget);
    expect(find.text('Questions 5, 6, 7, 8'), findsOneWidget);

    // Verify ONLY the two scan action buttons exist
    expect(find.text('Capture Mark Sheet'), findsOneWidget);
    expect(find.text('Upload Table Image'), findsOneWidget);
    expect(find.text('Open Camera'), findsOneWidget);
    expect(find.text('Browse Gallery'), findsOneWidget);

    // Verify previous demo button is gone
    expect(find.text('Try with Sample Marks Table (Demo)'), findsNothing);
  });

  testWidgets('Sign up opens the home screen without a database', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MarkSheetApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign up').first);
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Demo User');
    await tester.enterText(fields.at(1), 'new.user@example.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.enterText(fields.at(3), 'password123');
    final createAccountButton =
        find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('MarkSheet OCR'), findsOneWidget);
    expect(find.text('Exam MarkSheet Scanner'), findsOneWidget);
  });

  testWidgets('Sample preview opens mark review without OCR', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ImageProcessingScreen()),
    );
    await tester.pumpAndSettle();

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Marksheet Preview'), findsOneWidget);
    expect(find.text('Image preview ready'), findsWidgets);
    await tester.tap(find.text('Review Marks'));
    await tester.pumpAndSettle();

    expect(find.text('Verify Handwritten Marks'), findsOneWidget);
    expect(find.text('30'), findsWidgets);
  });

  testWidgets(
      'VerificationScreen renders Q1-Q4 and Q5-Q8 and treats N/A as 0 in totals',
      (WidgetTester tester) async {
    // Dynamic data with Q5-Q8 marks matching user's rubric
    final testData = MarksTableData.empty(tableType: '5-8').copyWith(
      cellMarks: {
        '5': {
          'a': '10',
          'b': '13',
          'c': '07',
          'd': 'N/A',
          'e': 'N/A',
          'f': 'N/A',
          'g': 'N/A'
        },
        '6': {
          'a': 'N/A',
          'b': 'N/A',
          'c': 'N/A',
          'd': 'N/A',
          'e': 'N/A',
          'f': 'N/A',
          'g': 'N/A'
        },
        '7': {
          'a': '12',
          'b': '04',
          'c': '06',
          'd': '08',
          'e': 'N/A',
          'f': 'N/A',
          'g': 'N/A'
        },
        '8': {
          'a': '09',
          'b': '05',
          'c': '17',
          'd': 'N/A',
          'e': 'N/A',
          'f': 'N/A',
          'g': 'N/A'
        },
        '1': {
          'a': '10',
          'b': '13',
          'c': '07',
          'd': 'N/A',
          'e': 'N/A',
          'f': 'N/A',
          'g': 'N/A'
        },
        '2': {
          'a': 'N/A',
          'b': 'N/A',
          'c': 'N/A',
          'd': 'N/A',
          'e': 'N/A',
          'f': 'N/A',
          'g': 'N/A'
        },
        '3': {
          'a': '12',
          'b': '04',
          'c': '06',
          'd': '08',
          'e': 'N/A',
          'f': 'N/A',
          'g': 'N/A'
        },
        '4': {
          'a': '09',
          'b': '05',
          'c': '17',
          'd': 'N/A',
          'e': 'N/A',
          'f': 'N/A',
          'g': 'N/A'
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VerificationScreen(
          marksTableData: testData,
          isSampleDemo: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify rubric elements for 5-8
    expect(find.text('Verify Handwritten Marks'), findsOneWidget);
    expect(find.text('Marks (on)'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.text('8'), findsWidgets);

    // Initial grand total calculated dynamically (30 + 0 + 30 + 31 = 91)
    expect(find.text('91'), findsWidgets);

    // Switch table format to Q1-Q4
    await tester.tap(find.text('Q1 – Q4'));
    await tester.pumpAndSettle();

    // Verify columns switched to 1, 2, 3, 4
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.text('4'), findsWidgets);

    // Switch back to Q5-Q8
    await tester.tap(find.text('Q5 – Q8'));
    await tester.pumpAndSettle();

    // Find first TextField (Q5, part a = '10') and change it to 'N/A'
    final firstField = find.byType(TextField).first;
    await tester.enterText(firstField, 'N/A');
    await tester.pumpAndSettle();

    // Grand total should decrease by 10: 91.0 - 10.0 = 81 (N/A is evaluated as 0)
    expect(find.text('81'), findsWidgets);

    // Enter a non-numeric string (e.g. 'invalid_text') -> should still calculate as 0
    await tester.enterText(firstField, 'xyz');
    await tester.pumpAndSettle();
    expect(find.text('81'), findsWidgets);

    // Tap Verify & Submit
    final submitBtn = find.text('Verify & Submit');
    await tester.ensureVisible(submitBtn);
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    // Verify Success Modal
    expect(find.text('Marks Verified & Computed!'), findsOneWidget);
    expect(find.text('Scan Another Mark Sheet'), findsOneWidget);
  });
}
