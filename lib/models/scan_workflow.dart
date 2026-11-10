import 'marks_table_data.dart';

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
