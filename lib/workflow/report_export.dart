import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'export_file.dart';
import 'results_excel_export.dart';

abstract interface class ReportExporter {
  Future<void> export(
      BuildContext context, String title, List<List<String>> rows);
}

String reportExcelXml(List<List<String>> rows) {
  final sheets = <String, List<List<String>>>{};
  var section = 'Report details';
  for (final row in rows) {
    if (row.isEmpty) continue;
    if (row.length >= 2) {
      section = switch ((row[0], row[1])) {
        ('Roll no', 'CO1') => 'Student CO attainment',
        ('CO', 'Eligible') => 'CO attainment',
        ('PO', 'Contribution %') => 'PO contributions',
        ('Course', 'PO') => 'Course breakdown',
        _ when row.length == 2 && row.first == 'Course PO contribution' =>
          'PO contributions',
        _ => section,
      };
    }
    final destination = row.length == 2 &&
            (row.first == 'Generated at (UTC)' || row.first == 'Scope')
        ? 'Report details'
        : section;
    sheets.putIfAbsent(destination, () => []).add(row);
  }
  return workbookExcelXml(sheets);
}

class ShareReportExporter implements ReportExporter {
  const ShareReportExporter();
  @override
  Future<void> export(
      BuildContext context, String title, List<List<String>> rows) async {
    final bytes = Uint8List.fromList(utf8.encode(reportExcelXml(rows)));
    final name = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    await exportFile(context, bytes,
        name: '$name-attainment.xls',
        mimeType: 'application/vnd.ms-excel',
        title: title);
  }
}
