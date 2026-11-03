import 'package:flutter/material.dart';

/// Spreadsheet-style marks grid with questions as rows and parts as columns.
class MarksGridTable extends StatelessWidget {
  final Map<String, Map<String, String>> marks;

  const MarksGridTable({super.key, required this.marks});

  static const _parts = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questions = marks.keys.toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    final border = TableBorder.all(color: theme.colorScheme.outlineVariant);

    Widget cell(String value, {bool header = false, bool rowHeader = false}) =>
        Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            color: header
                ? theme.colorScheme.surfaceContainerHighest
                : rowHeader
                    ? theme.colorScheme.surfaceContainerLow
                    : null,
            child: Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: header || rowHeader
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
              ]),
              for (final question in questions)
                TableRow(children: [
                  cell('Q$question', rowHeader: true),
                  for (final part in _parts)
                    cell(marks[question]?[part] ?? 'N/A'),
                ]),
            ]));
  }
}
