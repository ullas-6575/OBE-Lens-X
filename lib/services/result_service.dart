import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ResultService {
  Future<List<Map<String, dynamic>>> fetchResults();

  Future<void> saveResult({
    required String rollNo,
    required String submissionId,
    required String tableType,
    required Map<String, Map<String, String>> marks,
    required double grandTotal,
  });
}

bool savedResultMatches(
  Map<String, dynamic> saved, {
  required String rollNo,
  required String tableType,
  required Map<String, Map<String, String>> marks,
  required double grandTotal,
}) {
  final savedMarks = saved['marks'];
  if (saved['roll_no'] != rollNo ||
      saved['table_type'] != tableType ||
      saved['grand_total'] is! num ||
      (saved['grand_total'] as num).toDouble() != grandTotal ||
      savedMarks is! Map ||
      savedMarks.length != marks.length) {
    return false;
  }
  for (final question in marks.entries) {
    final savedParts = savedMarks[question.key];
    if (savedParts is! Map || savedParts.length != question.value.length) {
      return false;
    }
    for (final part in question.value.entries) {
      if (savedParts[part.key] != part.value) return false;
    }
  }
  return true;
}

class SupabaseResultService implements ResultService {
  const SupabaseResultService();

  @override
  Future<List<Map<String, dynamic>>> fetchResults() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      throw StateError('Sign in to view saved results.');
    }

    final response = await client
        .from('results')
        .select()
        .isFilter('exam_id', null)
        .order('created_at', ascending: false);

    return response
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<void> saveResult({
    required String rollNo,
    required String submissionId,
    required String tableType,
    required Map<String, Map<String, String>> marks,
    required double grandTotal,
  }) async {
    final trimmedRollNo = rollNo.trim();
    if (trimmedRollNo.isEmpty) {
      throw ArgumentError.value(rollNo, 'rollNo', 'Must not be empty.');
    }

    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      throw StateError('Sign in before saving a result.');
    }

    await client.from('results').upsert({
      'roll_no': trimmedRollNo,
      'submission_id': submissionId,
      'table_type': tableType,
      'marks': marks,
      'grand_total': grandTotal,
    }, onConflict: 'teacher_id,submission_id', ignoreDuplicates: true);

    final saved = await client
        .from('results')
        .select('roll_no, table_type, marks, grand_total')
        .eq('teacher_id', client.auth.currentUser!.id)
        .eq('submission_id', submissionId)
        .isFilter('exam_id', null)
        .maybeSingle();
    if (saved == null ||
        !savedResultMatches(
          saved,
          rollNo: trimmedRollNo,
          tableType: tableType,
          marks: marks,
          grandTotal: grandTotal,
        )) {
      throw StateError(
          'This submission ID was already saved with different values. Start a new scan.');
    }
  }
}
