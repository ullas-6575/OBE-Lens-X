import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'export_file.dart';

import 'models.dart';

/// Builds an Excel-readable SpreadsheetML workbook with one row per roll number.
String resultsExcelXml(Exam exam, List<Json> results) {
  final mappings = [...exam.questions]..sort((a, b) {
      final questionOrder =
          int.parse(a.question).compareTo(int.parse(b.question));
      return questionOrder != 0 ? questionOrder : a.part.compareTo(b.part);
    });
  final columns = mappings.map((q) => '${q.question}${q.part}').toList();
  final byRoll = <String, Map<String, Json>>{};
  for (final result in results) {
    final roll = result['roll_no'].toString();
    byRoll.putIfAbsent(roll, () => {})[result['table_type'].toString()] =
        result;
  }
  final rolls = byRoll.keys.toList()..sort();

  String cell(String value) =>
      '<Cell><Data ss:Type="String">${_xmlEscape(value)}</Data></Cell>';
  final output = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>')
    ..write('<?mso-application progid="Excel.Sheet"?>')
    ..write('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">')
    ..write('<Worksheet ss:Name="Results"><Table>')
    ..write('<Row>${cell('Roll')}${columns.map(cell).join()}</Row>');

  for (final roll in rolls) {
    final groups = byRoll[roll]!;
    final values = <String>[roll];
    for (final mapping in mappings) {
      final result = groups[mapping.group];
      final marks = result?['marks'];
      final questionMarks = marks is Map ? marks[mapping.question] : null;
      final mark = questionMarks is Map ? questionMarks[mapping.part] : null;
      values.add(mark?.toString() ?? '');
    }
    output.write('<Row>${values.map(cell).join()}</Row>');
  }
  output.write('</Table></Worksheet></Workbook>');
  return output.toString();
}

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

Future<void> shareResultsExcel(BuildContext context, String examName, Exam exam,
    List<Json> results) async {
  final bytes = Uint8List.fromList(utf8.encode(resultsExcelXml(exam, results)));
  await exportFile(context, bytes,
      name: '${_safeFileName(examName)}-results.xls',
      mimeType: 'application/vnd.ms-excel',
      title: '$examName results');
}

String _safeFileName(String value) => value
    .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
    .trim()
    .replaceAll(RegExp(r'\s+'), '_');
