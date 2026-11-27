import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'export_file.dart';

import 'models.dart';

/// Merges question groups into one row per roll for the selected exam.
List<List<String>> resultsWorksheet(Exam exam, List<Json> results) {
  final mappings = [...exam.questions]..sort((a, b) {
      final questionOrder =
          int.parse(a.question).compareTo(int.parse(b.question));
      return questionOrder != 0 ? questionOrder : a.part.compareTo(b.part);
    });
  final columns = mappings.map((q) => '${q.question}${q.part}').toList();
  final byRoll = <String, Map<String, Json>>{};
  for (final result in results) {
    if (result['exam_id'] != exam.id) continue;
    final roll = result['roll_no'].toString();
    byRoll.putIfAbsent(roll, () => {})[result['table_type'].toString()] =
        result;
  }
  final rolls = byRoll.keys.toList()
    ..sort((a, b) {
      final first = int.tryParse(a), second = int.tryParse(b);
      if (first == null && second != null) return 1;
      if (first != null && second == null) return -1;
      final order = first != null && second != null
          ? first.compareTo(second)
          : a.compareTo(b);
      return order == 0 ? a.compareTo(b) : order;
    });
  final rows = <List<String>>[
    ['Roll', ...columns],
  ];

  for (final roll in rolls) {
    final groups = byRoll[roll]!;
    final values = <String>[roll];
    for (final mapping in mappings) {
      final result = groups[mapping.group];
      final marks = result?['marks'];
      final questionMarks = marks is Map ? marks[mapping.question] : null;
      final mark = questionMarks is Map ? questionMarks[mapping.part] : null;
      values.add(mark?.toString() ?? 'N/A');
    }
    rows.add(values);
  }
  return rows;
}

/// String cells preserve roll numbers, leading zeroes and literal formulas.
String workbookExcelXml(Map<String, List<List<String>>> sheets) {
  final escape = const HtmlEscape(HtmlEscapeMode.element).convert;
  final attribute = const HtmlEscape(HtmlEscapeMode.attribute).convert;
  String cell(String value) =>
      '<Cell><Data ss:Type="String">${escape(value)}</Data></Cell>';
  final output = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>')
    ..write('<?mso-application progid="Excel.Sheet"?>')
    ..write('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" '
        'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">');
  for (final sheet in sheets.entries) {
    final sheetName = sheet.key.replaceAll(RegExp(r'[\[\]:*?/\\]'), '_').trim();
    final safeName = sheetName.isEmpty ? 'Sheet1' : sheetName;
    output
      ..write(
          '<Worksheet ss:Name="${attribute(safeName.substring(0, safeName.length > 31 ? 31 : safeName.length))}"><Table>')
      ..write(
          sheet.value.map((row) => '<Row>${row.map(cell).join()}</Row>').join())
      ..write('</Table></Worksheet>');
  }
  output.write('</Workbook>');
  return output.toString();
}

String worksheetExcelXml(String name, List<List<String>> rows) =>
    workbookExcelXml({name: rows});

String resultsExcelXml(Exam exam, List<Json> results) =>
    worksheetExcelXml('Results', resultsWorksheet(exam, results));

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
