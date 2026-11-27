import 'package:flutter/material.dart';

String worksheetColumnName(int index) {
  var name = '';
  for (var number = index + 1; number > 0; number = (number - 1) ~/ 26) {
    name = String.fromCharCode(65 + (number - 1) % 26) + name;
  }
  return name;
}

class WorksheetGrid extends StatelessWidget {
  final List<List<String>> rows;
  final bool headerRow, keyValue;
  final ValueChanged<int>? onRowTap;
  const WorksheetGrid(
      {super.key,
      required this.rows,
      this.headerRow = false,
      this.keyValue = false,
      this.onRowTap});

  @override
  Widget build(BuildContext context) {
    final columnCount = rows.fold<int>(
        0, (count, row) => row.length > count ? row.length : count);
    final dataWidths = keyValue
        ? [220.0, 360.0]
        : rows.first.first == 'Roll'
            ? [150.0, ...List.filled(columnCount - 1, 80.0)]
            : switch (columnCount) {
                5 when rows.first.first == 'Roll no' => [
                    150.0,
                    100.0,
                    100.0,
                    100.0,
                    100.0
                  ],
                5 => [96.0, 104.0, 104.0, 150.0, 126.0],
                4 => [150.0, 100.0, 150.0, 120.0],
                3 => [110.0, 170.0, 170.0],
                _ => [140.0, 220.0],
              };
    final widths = <double>[
      42,
      for (var index = 0; index < columnCount; index++)
        index < dataWidths.length ? dataWidths[index] : 120,
    ];
    final dataRows = <List<String>>[
      [
        '',
        for (var index = 0; index < columnCount; index++)
          worksheetColumnName(index),
      ],
      ...rows.asMap().entries.map((entry) => [
            '${entry.key + 1}',
            ...entry.value,
            ...List.filled(columnCount - entry.value.length, ''),
          ]),
    ];
    final border = Border.all(color: const Color(0xFFD8E0DA), width: 0.7);

    return Material(
        color: Colors.transparent,
        child: LayoutBuilder(builder: (context, constraints) {
          final naturalWidth =
              widths.fold<double>(0, (sum, width) => sum + width);
          final sheetWidth = naturalWidth > constraints.maxWidth
              ? naturalWidth
              : constraints.maxWidth;
          return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                  width: sheetWidth,
                  child: Table(
                      border: TableBorder(
                          top: border.top,
                          bottom: border.bottom,
                          left: border.left,
                          right: border.right,
                          horizontalInside: border.top,
                          verticalInside: border.left),
                      columnWidths: {
                        for (var index = 0; index < widths.length; index++)
                          index: FixedColumnWidth(widths[index]),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        for (var rowIndex = 0;
                            rowIndex < dataRows.length;
                            rowIndex++)
                          TableRow(children: [
                            for (var columnIndex = 0;
                                columnIndex < dataRows[rowIndex].length;
                                columnIndex++) ...[
                              Builder(builder: (context) {
                                final value = dataRows[rowIndex][columnIndex];
                                final baseColor = rowIndex == 0
                                    ? const Color(0xFFE8EEE9)
                                    : columnIndex == 0
                                        ? const Color(0xFFF0F3F1)
                                        : headerRow && rowIndex == 1
                                            ? const Color(0xFFE4F0E8)
                                            : (rowIndex.isEven
                                                ? const Color(0xFFFAFCFA)
                                                : Colors.white);
                                return Tooltip(
                                    message: value,
                                    child: InkWell(
                                        onTap: onRowTap != null &&
                                                columnIndex == 1 &&
                                                rowIndex > (headerRow ? 1 : 0)
                                            ? () => onRowTap!(
                                                rowIndex - (headerRow ? 2 : 1))
                                            : null,
                                        child: Container(
                                            constraints: const BoxConstraints(
                                                minHeight: 38),
                                            color: baseColor,
                                            alignment: columnIndex <= 1 ||
                                                    keyValue ||
                                                    (headerRow && rowIndex == 1)
                                                ? Alignment.centerLeft
                                                : Alignment.centerRight,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 9),
                                            child: Text(value,
                                                softWrap: keyValue,
                                                overflow: keyValue
                                                    ? null
                                                    : TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: const Color(0xFF26352C),
                                                    fontSize: rowIndex == 0 ? 11 : 13,
                                                    fontWeight: rowIndex == 0 || (headerRow && rowIndex == 1) || (keyValue && columnIndex == 0) ? FontWeight.w600 : FontWeight.normal)))));
                              }),
                            ],
                          ]),
                      ])));
        }));
  }
}
