import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/services/local_preview_services.dart';
import 'package:my_app/screens/image_source_screen.dart';
import 'package:my_app/widgets/marks_grid_table.dart';
import 'package:my_app/workflow/models.dart';
import 'package:my_app/workflow/repository.dart';
import 'package:my_app/workflow/results_excel_export.dart';
import 'package:my_app/workflow/scan_pages.dart';

import 'support/workflow_fakes.dart';

const sharedExam =
    Exam(id: 'exam', offeringId: 'offering', name: 'Shared final', questions: [
  QuestionMapping('1', 'a', 'CO1', 10),
  QuestionMapping('5', 'a', 'CO1', 10),
]);
const scan = ScanContext(sampleCourse, sampleOffering, sharedExam, 'ROLL001');

MarksTableData marks(String group, String value) {
  final data = MarksTableData.empty(tableType: group);
  data.cellMarks[group == '1-4' ? '1' : '5']!['a'] = value;
  return data;
}

FakeWorkflowRepository sharedRepository() => seededRepository()
  ..resultRows.addAll([
    {
      'id': 'first',
      'exam_id': 'exam',
      'roll_no': 'ROLL001',
      'table_type': '1-4',
      'marks': marks('1-4', '5').cellMarks,
      'grand_total': 5,
      'revision': 1,
    },
    {
      'id': 'second',
      'exam_id': 'exam',
      'roll_no': 'ROLL001',
      'table_type': '5-8',
      'marks': marks('5-8', '7').cellMarks,
      'grand_total': 7,
      'revision': 1,
    },
  ]);

void main() {
  Future<void> submit(WidgetTester tester, FakeWorkflowRepository repo) async {
    await tester.pumpWidget(MaterialApp(
        home: SubmissionPage(
            repository: repo, scan: scan, data: marks('1-4', '9'))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save result'));
    await tester.tap(find.text('Save result'));
    await tester.pumpAndSettle();
  }

  test('Different groups add to one student worksheet row', () async {
    final repo = seededRepository();
    await repo.saveMarks(
        scan, 'first-upload', '1-4', marks('1-4', '5').cellMarks);
    await repo.saveMarks(
        scan, 'second-upload', '5-8', marks('5-8', '7').cellMarks);
    expect(resultsWorksheet(sharedExam, await repo.results('exam')), [
      ['Roll', '1a', '5a'],
      ['ROLL001', '5', '7'],
    ]);
  });

  test('Local preview also confirms replacements and accepts retries',
      () async {
    final repo = LocalPreviewWorkflowRepository();
    final course = (await repo.courses()).first;
    final offering = (await repo.offerings(course.id)).first;
    final exam = (await repo.exams(offering.id)).first;
    final question = exam.questions.first;
    final context = ScanContext(course, offering, exam, 'SHARED_TEST');
    final original = MarksTableData.empty(tableType: question.group).cellMarks;
    original[question.question]![question.part] = '0';
    await repo.saveMarks(context, 'original', question.group, original);
    final replacement =
        MarksTableData.empty(tableType: question.group).cellMarks;
    replacement[question.question]![question.part] = '1';
    await expectLater(
        repo.saveMarks(context, 'replacement', question.group, replacement),
        throwsA(isA<ResultConflict>()));
    final previous = (await repo.results(exam.id))
        .singleWhere((row) => row['roll_no'] == 'SHARED_TEST');
    await repo.saveMarks(context, 'replacement', question.group, replacement,
        previous: previous);
    await repo.saveMarks(context, 'replacement', question.group, replacement,
        previous: previous);
    final saved = (await repo.results(exam.id))
        .singleWhere((row) => row['roll_no'] == 'SHARED_TEST');
    expect(saved['revision'], 2);
    expect(saved['grand_total'], 1);
    await expectLater(
        repo.saveMarks(context, 'new-upload', question.group, replacement),
        throwsA(isA<ResultConflict>()));
  });

  for (final replace in [false, true]) {
    testWidgets(
        'Duplicate upload can ${replace ? 'replace' : 'keep'} its group',
        (tester) async {
      final repo = sharedRepository();
      await submit(tester, repo);
      expect(find.text('Replace previous marks?'), findsOneWidget);
      expect(repo.resultRows.first['revision'], 1);
      expect((repo.resultRows.first['marks'] as Map)['1']['a'], '5');
      await tester.tap(find.text(replace ? 'Replace marks' : 'Keep previous'));
      await tester.pumpAndSettle();
      expect(find.text(replace ? 'Result saved' : 'Previous marks kept'),
          findsOneWidget);
      expect(repo.resultRows.length, 2);
      expect(repo.resultRows.first['revision'], replace ? 2 : 1);
      expect((repo.resultRows.first['marks'] as Map)['1']['a'],
          replace ? '9' : '5');
      expect((repo.resultRows.last['marks'] as Map)['5']['a'], '7');
      expect(repo.resultRows.last['revision'], 1);
      expect(
          tester
              .widget<MarksGridTable>(find.byType(MarksGridTable))
              .marks['1']!['a'],
          replace ? '9' : '5');
      if (replace) expect(repo.submissions[0], repo.submissions[1]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('A changed group asks again instead of overwriting newer marks',
      (tester) async {
    final repo = sharedRepository();
    await submit(tester, repo);
    repo.resultRows[0] = {
      ...repo.resultRows[0],
      'marks': marks('1-4', '6').cellMarks,
      'grand_total': 6,
      'revision': 2,
    };
    await tester.tap(find.text('Replace marks'));
    await tester.pumpAndSettle();
    expect(find.text('Replace previous marks?'), findsOneWidget);
    expect((repo.resultRows.first['marks'] as Map)['1']['a'], '6');
    await tester.tap(find.text('Keep previous'));
    await tester.pumpAndSettle();
    expect(find.text('Previous marks kept'), findsOneWidget);
    expect(repo.resultRows.first['revision'], 2);
    expect(
        tester
            .widget<MarksGridTable>(find.byType(MarksGridTable))
            .marks['1']!['a'],
        '6');
  });

  for (final complete in [false, true]) {
    testWidgets(
        'Scanner allows a new upload when ${complete ? 'both groups exist' : 'one group exists'}',
        (tester) async {
      final repo = sharedRepository();
      if (!complete) repo.resultRows.removeLast();
      await tester.pumpWidget(
          MaterialApp(home: StudentScanPage(repository: repo, scan: scan)));
      await tester.pumpAndSettle();
      final source =
          tester.widget<ImageSourceScreen>(find.byType(ImageSourceScreen));
      expect(
          source.workflow!.groups, complete ? ['1-4', '5-8'] : ['5-8', '1-4']);
      expect(tester.takeException(), isNull);
    });
  }

  test('Supabase save maps conflicts and sends the exact confirmed revision',
      () async {
    final previous = sharedRepository().resultRows.first;
    var calls = 0;
    final client = SupabaseClient('https://example.supabase.co', 'test-key',
        httpClient: MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/save_question_group');
      final payload = jsonDecode(request.body) as Map;
      if (calls++ == 0) {
        expect(payload.containsKey('p_result_id'), isFalse);
        return http.Response(
            jsonEncode({'status': 'conflict', 'previous': previous}), 200,
              request: request,
            headers: {'content-type': 'application/json'});
      }
      expect(payload['p_result_id'], 'first');
      expect(payload['p_result_revision'], 1);
      return http.Response('{"status":"saved","id":"first"}', 200,
            request: request,
          headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    final repo = SupabaseWorkflowRepository(client);
    await expectLater(
        repo.saveMarks(scan, 'upload', '1-4', marks('1-4', '9').cellMarks),
        throwsA(isA<ResultConflict>()));
    await repo.saveMarks(scan, 'upload', '1-4', marks('1-4', '9').cellMarks,
        previous: previous);
    expect(calls, 2);
  });
}
