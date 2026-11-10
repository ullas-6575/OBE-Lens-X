import 'package:flutter/material.dart';
import '../models/marks_table_data.dart';

/// Spreadsheet-style marks grid with questions as rows and parts as columns.
class MarksGridTable extends StatelessWidget {
  final Map<String, Map<String, String>> marks;
  final bool showTotals;

  const MarksGridTable(
      {super.key, required this.marks, this.showTotals = false});

  static const _parts = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questions = marks.keys.toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    final border = TableBorder.all(color: theme.colorScheme.outlineVariant);
    final questionTotals = {
      for (final question in questions)
        question: _parts.fold<double>(
            0,
            (total, part) =>
                total + MarksTableData.parseMarkValue(marks[question]?[part])),
    };
    final partTotals = {
      for (final part in _parts)
        part: questions.fold<double>(
            0,
            (total, question) =>
                total + MarksTableData.parseMarkValue(marks[question]?[part])),
    };
    final grandTotal = questionTotals.values.fold<double>(0, (a, b) => a + b);

    Widget cell(String value,
            {bool header = false,
            bool rowHeader = false,
            bool total = false,
            Key? key}) =>
        Container(
            key: key,
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            color: header
                ? theme.colorScheme.surfaceContainerHighest
                : total
                    ? theme.colorScheme.primaryContainer
                    : rowHeader
                        ? theme.colorScheme.surfaceContainerLow
                        : null,
            child: Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: header || rowHeader || total
                        ? FontWeight.w600
                        : FontWeight.normal)));

    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
            border: border,
            defaultColumnWidth: const FixedColumnWidth(82),
            columnWidths: const {
              0: FixedColumnWidth(92)
            },
            children: [
              TableRow(children: [
                cell('Question', header: true),
                for (final part in _parts) cell(part, header: true),
                if (showTotals) cell('Total', header: true),
              ]),
              for (final question in questions)
                TableRow(children: [
                  cell('Q$question', rowHeader: true),
                  for (final part in _parts)
                    cell(marks[question]?[part] ?? 'N/A'),
                  if (showTotals)
                    cell(questionTotals[question]!.toStringAsFixed(0),
                        total: true, key: ValueKey('question-total-$question')),
                ]),
              if (showTotals)
                TableRow(children: [
                  cell('Total', total: true),
                  for (final part in _parts)
                    cell(partTotals[part]!.toStringAsFixed(0), total: true),
                  cell(grandTotal.toStringAsFixed(0),
                      total: true, key: const ValueKey('grid-grand-total')),
                ]),
            ]));
  }
}
