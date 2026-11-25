import 'dart:math';

import 'marks_table_data.dart';

/// Unique save token shared by the scanner and the standalone review flow.
String newSubmissionId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Optional integration contract. Standalone scanning remains usable without a course.
class ScanWorkflow {
  static const scannerRoute = '/scanner';
  final String rollNo, description;
  final List<String> groups;
  final Future<void> Function(MarksTableData data) review;
  final String? Function(String group, Map<String, Map<String, String>> marks)
      validate;
  const ScanWorkflow(
      {required this.rollNo,
      required this.description,
      required this.groups,
      required this.review,
      required this.validate});
}
