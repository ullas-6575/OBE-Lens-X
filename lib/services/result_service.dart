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
    required String tableType,
    required Map<String, Map<String, String>> marks,
    required double grandTotal,
    String? imagePath,
  }) async {
    final trimmedRollNo = rollNo.trim();
    if (trimmedRollNo.isEmpty) {
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
  }
}
