import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/screens/results_screen.dart';
import 'package:my_app/services/result_service.dart';

class _Results implements ResultService {
  int reads = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchResults() async {
    reads++;
    return [
      {
        'roll_no': 'ROLL001',
        'table_type': '1-4',
        'grand_total': 15,
        'created_at': '2026-10-13T12:30:00Z',
      },
    ];
  }

  @override
  Future<void> saveResult({
    required String rollNo,
    required String submissionId,
    required String tableType,
    required Map<String, Map<String, String>> marks,
    required double grandTotal,
    String? imagePath,
  }) async {}
}

void main() {
  testWidgets('Rebuilding results keeps the existing database request',
      (tester) async {
    final service = _Results();
    Widget screen() => MaterialApp(home: ResultsScreen(resultService: service));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(service.reads, 1);
    expect(find.text('ROLL001'), findsOneWidget);

    final replacement = _Results();
    await tester.pumpWidget(
        MaterialApp(home: ResultsScreen(resultService: replacement)));
    await tester.pumpAndSettle();
    expect(replacement.reads, 1);
  });
}
