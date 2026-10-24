import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

abstract interface class ReportExporter {
  Future<void> export(
      BuildContext context, String title, List<List<String>> rows,
      {required bool pdf});
}

String reportCsv(List<List<String>> rows) => rows
    .map((row) => row.map((cell) {
          // Prevent spreadsheet formula execution, including whitespace-prefixed formulas.
          final safe =
              RegExp(r'^\s*[=+@\-\t\r\n]').hasMatch(cell) ? "'$cell" : cell;
          return '"${safe.replaceAll('"', '""')}"';
        }).join(','))
    .join('\r\n');

class ShareReportExporter implements ReportExporter {
  const ShareReportExporter();
  @override
  Future<void> export(
      BuildContext context, String title, List<List<String>> rows,
      {required bool pdf}) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final Uint8List bytes;
    if (pdf) {
      final document = pw.Document();
      // Core PDF fonts cover Latin text. Keep identifiers readable without network font downloads.
      String latin(String s) => s
          .replaceAll('→', ' -> ')
          .replaceAll('·', ' / ')
          .replaceAll('–', '-')
          .replaceAll(RegExp(r'[^\x20-\x7E\n]'), '?');
      document.addPage(pw.MultiPage(
          build: (_) => [
                pw.Header(level: 0, child: pw.Text(latin(title))),
                pw.TableHelper.fromTextArray(
                    data: rows.map((r) => r.map(latin).toList()).toList()),
              ]));
      bytes = await document.save();
    } else {
      bytes = Uint8List.fromList(utf8.encode('\uFEFF${reportCsv(rows)}'));
    }
    await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: pdf ? 'application/pdf' : 'text/csv')],
        fileNameOverrides: ['obelens-report.${pdf ? 'pdf' : 'csv'}'],
        subject: title,
        sharePositionOrigin: origin);
  }
}
