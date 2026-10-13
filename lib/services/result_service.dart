<<<<<<< HEAD
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ResultService {
  Future<List<Map<String, dynamic>>> fetchResults();

  Future<void> saveResult({
    required String rollNo,
    required String submissionId,
    required String tableType,
    required Map<String, Map<String, String>> marks,
    required double grandTotal,
    String? imagePath,
  });
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
        .order('created_at', ascending: false);

    return response
        .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<void> saveResult({
    required String rollNo,
    required String submissionId,
=======
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResultService {
  static Future<List<Map<String, dynamic>>> fetchResults() async {
    try {
      final response = await Supabase.instance.client
          .from('results')
          .select()
          .order('created_at', ascending: false);

      return response
          .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (error, stackTrace) {
      debugPrint('Failed to fetch results: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const [];
    }
  }

  static Future<bool> saveResult({
    required String rollNo,
>>>>>>> e4c15a2d94824aa614f80e0d233b8351328af5b1
    required String tableType,
    required Map<String, Map<String, String>> marks,
    required double grandTotal,
    String? imagePath,
  }) async {
    final trimmedRollNo = rollNo.trim();
    if (trimmedRollNo.isEmpty) {
<<<<<<< HEAD
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
      'image_path': imagePath,
    }, onConflict: 'teacher_id,submission_id', ignoreDuplicates: true);
=======
      return false;
    }

    try {
      final response = await Supabase.instance.client.from('results').insert({
        'roll_no': trimmedRollNo,
        'table_type': tableType,
        'marks': marks,
        'grand_total': grandTotal,
        'image_path': imagePath,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).select();

      return response.isNotEmpty;
    } catch (error, stackTrace) {
      debugPrint('Failed to save result: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
>>>>>>> e4c15a2d94824aa614f80e0d233b8351328af5b1
  }
}
