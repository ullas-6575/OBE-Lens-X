import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'export_file.dart';

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

Future<Uint8List> reportPdf(String title, List<List<String>> rows) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/FreeSans.ttf'));
  final document =
      pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
  final columns = rows.fold<int>(
      1, (count, row) => row.length > count ? row.length : count);
  document.addPage(pw.MultiPage(
      build: (_) => [
            pw.Header(level: 0, child: pw.Text(title)),
            pw.TableHelper.fromTextArray(
                headerCount: 0,
                data: rows
                    .map((row) =>
                        [...row, ...List.filled(columns - row.length, '')])
                    .toList()),
          ]));
  return document.save();
}

class ShareReportExporter implements ReportExporter {
  const ShareReportExporter();
  @override
  Future<void> export(
      BuildContext context, String title, List<List<String>> rows,
      {required bool pdf}) async {
    final Uint8List bytes;
    if (pdf) {
      bytes = await reportPdf(title, rows);
    } else {
      bytes = Uint8List.fromList(utf8.encode('\uFEFF${reportCsv(rows)}'));
    }
    if (!context.mounted) return;
    await exportFile(context, bytes,
        name: 'obelens-report.${pdf ? 'pdf' : 'csv'}',
        mimeType: pdf ? 'application/pdf' : 'text/csv',
        title: title);
  }
}
