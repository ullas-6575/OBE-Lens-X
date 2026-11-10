import 'dart:convert';
import 'package:flutter/material.dart';
import 'models.dart';
import 'repository.dart';
import 'attainment.dart';
import 'report_export.dart';
import 'ui.dart';

class ReportSnapshot {
  final String fingerprint, title;
  final List<List<String>> rows;
  final List<String> issues;
  final bool exportable;
  final AttainmentReport? attainment;
  const ReportSnapshot(
      this.fingerprint, this.title, this.rows, this.issues, this.exportable,
      {this.attainment});
}

Future<ReportSnapshot> loadExamReport(WorkflowRepository repository,
    Course previous, Offering offering, Exam previousExam) async {
  final course =
      (await repository.courses()).firstWhere((c) => c.id == previous.id);
  final exam = (await repository.exams(offering.id))
      .firstWhere((e) => e.id == previousExam.id);
  final results = await repository.results(exam.id);
  final report = const AttainmentCalculator().calculate(course, exam, results);
  final rows = <List<String>>[
    ['Course', '${course.code} ${course.title}'],
    ['Offering', offering.label],
    ['Exam', exam.name],
    ['Exam revision', '${exam.revision}'],
    ['Score threshold', '${exam.policy.scoreThreshold}%'],
    ['CO target', '${exam.policy.targetPercent}%'],
    ['Required groups', exam.requiredGroups.join(', ')],
    [
      'Students / incomplete excluded',
      '${report.students} / ${report.excluded}'
    ],
    ['CO', 'Eligible', 'Attained', 'Attainment %', 'Target met'],
    for (final score in report.outcomes)
      [
        score.code,
        '${score.eligible}',
        '${score.attained}',
        score.percent?.toStringAsFixed(2) ?? 'N/A',
        score.percent == null
            ? 'N/A'
            : score.percent! >= exam.policy.targetPercent
                ? 'Yes'
                : 'No'
      ],
    ['Course PO contribution', 'Equal mean of linked CO percentages'],
    for (final po in report.poContribution.entries)
      [po.key, po.value.toStringAsFixed(2)],
  ];
  final fingerprint = jsonEncode([
    course.code,
    course.title,
    course.outcomes.map((c) => c.toJson()).toList(),
    exam.revision,
    exam.policy.toJson(),
    exam.questions.map((q) => q.toJson()).toList(),
    results
  ]);
  return ReportSnapshot(fingerprint, '${course.code} - ${exam.name}', rows,
      report.issues, report.exportable,
      attainment: report);
}

class ReportPage extends StatefulWidget {
  final WorkflowRepository repository;
  final Course course;
  final Offering offering;
  final Exam exam;
  final ReportExporter exporter;
  const ReportPage(
      {super.key,
      required this.repository,
      required this.course,
      required this.offering,
      required this.exam,
      this.exporter = const ShareReportExporter()});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late Future<ReportSnapshot> _report = _load();
  Future<ReportSnapshot> _load() => loadExamReport(
      widget.repository, widget.course, widget.offering, widget.exam);
  void _reload() => setState(() {
        _report = _load();
      });
  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'Report preview', children: [
        LoadView(
            future: _report,
            retry: _reload,
            builder: (report) => ReportPreview(
                report: report,
                load: _load,
                onStale: _reload,
                exporter: widget.exporter)),
        TextButton(
            onPressed: _reload,
            child: const Text('Recalculate from latest marks and mappings')),
      ]);
}

class ReportPreview extends StatefulWidget {
  final ReportSnapshot report;
  final Future<ReportSnapshot> Function() load;
  final VoidCallback onStale;
  final ReportExporter exporter;
  const ReportPreview(
      {super.key,
      required this.report,
      required this.load,
      required this.onStale,
      required this.exporter});
  @override
  State<ReportPreview> createState() => _ReportPreviewState();
}

class _ReportPreviewState extends State<ReportPreview> {
  bool _busy = false;

  Future<void> _export(bool pdf) async {
    setState(() => _busy = true);
    try {
      final latest = await widget.load();
      if (!mounted) return;
      if (latest.fingerprint != widget.report.fingerprint ||
          !latest.exportable) {
        showError(context,
            'Marks or mappings changed. The report has been recalculated; review it before exporting.');
        widget.onStale();
        return;
      }
      await widget.exporter.export(
          context,
          latest.title,
          [
            ...latest.rows,
            ['Generated at (UTC)', DateTime.now().toUtc().toIso8601String()]
          ],
          pdf: pdf);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isTableHeader(List<String> row) =>
      row.length >= 2 &&
      ((row[0] == 'CO' && row[1] == 'Eligible') ||
          (row[0] == 'PO' && row[1] == 'Contribution %') ||
          (row[0] == 'Course' && row[1] == 'PO'));

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                color: Color(0xFF52645A),
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      );

  Widget _worksheetGrid(List<List<String>> rows,
      {bool headerRow = false, bool keyValue = false}) {
    final columnCount = rows.fold<int>(
        0, (count, row) => row.length > count ? row.length : count);
    final dataWidths = keyValue
        ? [220.0, 360.0]
        : switch (columnCount) {
            5 => [96.0, 104.0, 104.0, 150.0, 126.0],
            4 => [150.0, 100.0, 150.0, 120.0],
            3 => [110.0, 170.0, 170.0],
            _ => [140.0, 220.0],
          };
    final widths = <double>[42, ...dataWidths.take(columnCount)];
    final dataRows = <List<String>>[
      [
        '',
        for (var index = 0; index < columnCount; index++)
          String.fromCharCode(65 + index),
      ],
      ...rows.asMap().entries.map((entry) => [
            '${entry.key + 1}',
            ...entry.value,
            ...List.filled(columnCount - entry.value.length, ''),
          ]),
    ];
    final border = Border.all(color: const Color(0xFFD8E0DA), width: 0.7);

    return LayoutBuilder(builder: (context, constraints) {
      final naturalWidth = widths.fold<double>(0, (sum, width) => sum + width);
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
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
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
                                child: Container(
                                    constraints:
                                        const BoxConstraints(minHeight: 38),
                                    color: baseColor,
                                    alignment: columnIndex <= 1 ||
                                            keyValue ||
                                            (headerRow && rowIndex == 1)
                                        ? Alignment.centerLeft
                                        : Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 9),
                                    child: Text(value,
                                        style: TextStyle(
                                            color: const Color(0xFF26352C),
                                            fontSize: rowIndex == 0 ? 11 : 13,
                                            fontWeight: rowIndex == 0 ||
                                                    (headerRow &&
                                                        rowIndex == 1) ||
                                                    (keyValue &&
                                                        columnIndex == 0)
                                                ? FontWeight.w600
                                                : FontWeight.normal))));
                          }),
                        ],
                      ]),
                  ])));
    });
  }

  List<Widget> _worksheetContents() {
    final rows =
        widget.report.rows.where((row) => row.first != 'Scope').toList();
    final firstHeader = rows.indexWhere(_isTableHeader);
    final contents = <Widget>[];
    var index = 0;

    if (firstHeader < 0) {
      contents.add(_worksheetGrid(rows, keyValue: true));
      return contents;
    }
    if (firstHeader > 0) {
      contents
        ..add(_sectionTitle('Report details'))
        ..add(_worksheetGrid(rows.take(firstHeader).toList(), keyValue: true));
      index = firstHeader;
    }

    while (index < rows.length) {
      final row = rows[index];
      if (row.first == 'Course PO contribution') {
        contents.add(_sectionTitle(row.first));
        index++;
        final poRows = <List<String>>[
          ['PO', 'Contribution %'],
        ];
        while (index < rows.length) {
          poRows.add(rows[index++]);
        }
        contents.add(_worksheetGrid(poRows, headerRow: true));
        continue;
      }
      if (_isTableHeader(row)) {
        final title = switch (row.first) {
          'CO' => 'Course outcome attainment',
          'PO' => 'Program PO contribution',
          _ => 'Course breakdown',
        };
        contents.add(_sectionTitle(title));
        final tableRows = <List<String>>[row];
        index++;
        while (index < rows.length &&
            !_isTableHeader(rows[index]) &&
            rows[index].first != 'Course PO contribution') {
          tableRows.add(rows[index++]);
        }
        contents.add(_worksheetGrid(tableRows, headerRow: true));
        continue;
      }
      contents.add(_worksheetGrid([row], keyValue: true));
      index++;
    }
    return contents;
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final issue in widget.report.issues)
          Text(issue,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (!widget.report.exportable && widget.report.issues.isEmpty)
          const Text(
              'No eligible results yet. Export becomes available after eligible scripts are saved.'),
        Container(
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFBFCBC2)),
                borderRadius: BorderRadius.circular(3)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: const BoxDecoration(
                          color: Color(0xFF173F35),
                          border: Border(
                              bottom: BorderSide(color: Color(0xFF31594D)))),
                      child: Row(children: [
                        const Icon(Icons.grid_on,
                            size: 18, color: Color(0xFF9BDEA9)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(widget.report.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600))),
                        const Text('REPORT  /  XLS',
                            style: TextStyle(
                                color: Color(0xFFB7CCC1),
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ])),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _worksheetContents())),
                ])),
        Wrap(spacing: 12, children: [
          FilledButton(
              onPressed: !widget.report.exportable || _busy
                  ? null
                  : () => _export(true),
              child: const Text('Export PDF')),
          OutlinedButton(
              onPressed: !widget.report.exportable || _busy
                  ? null
                  : () => _export(false),
              child: const Text('Export spreadsheet (CSV)')),
        ]),
      ]);
}

class ProgramReportPage extends StatefulWidget {
  final WorkflowRepository repository;
  const ProgramReportPage({super.key, required this.repository});
  @override
  State<ProgramReportPage> createState() => _ProgramReportPageState();
}

class _ProgramReportPageState extends State<ProgramReportPage> {
  final _year = TextEditingController(), _term = TextEditingController();
  Future<ReportSnapshot>? _report;
  String _selectedYear = '', _selectedTerm = '';
  @override
  void dispose() {
    _year.dispose();
    _term.dispose();
    super.dispose();
  }

  Future<ReportSnapshot> _load() async {
    final courses = await widget.repository.courses();
    final poCourses = <String, List<double>>{};
    final issues = <String>[];
    final fingerprints = <Object>[];
    final detailRows = <List<String>>[];
    var included = 0;
    for (final course in courses) {
      final offerings = (await widget.repository.offerings(course.id))
          .where((o) => o.year == _selectedYear && o.term == _selectedTerm);
      for (final offering in offerings) {
        final exams = await widget.repository.exams(offering.id);
        if (exams.isEmpty) issues.add('${course.code}: no exams configured.');
        final coursePos = <String, List<double>>{};
        for (final exam in exams) {
          final snapshot =
              await loadExamReport(widget.repository, course, offering, exam);
          fingerprints.add(snapshot.fingerprint);
          if (!snapshot.exportable) {
            issues.add(
                '${course.code} / ${exam.name}: no eligible report or unresolved completeness/mapping issues.');
            continue;
          }
          // Aggregate domain values at full precision, independent of display/export text.
          for (final contribution
              in snapshot.attainment!.poContribution.entries) {
            coursePos
                .putIfAbsent(contribution.key, () => [])
                .add(contribution.value);
          }
        }
        if (coursePos.isNotEmpty) included++;
        for (final entry in coursePos.entries) {
          final mean = entry.value.reduce((a, b) => a + b) / entry.value.length;
          poCourses.putIfAbsent(entry.key, () => []).add(mean);
          detailRows.add([
            course.code,
            entry.key,
            mean.toStringAsFixed(2),
            '${entry.value.length} exams'
          ]);
        }
      }
    }
    final rows = <List<String>>[
      ['Program aggregation', '$_selectedYear / $_selectedTerm'],
      [
        'Method',
        'Equal mean of exam contributions within each course, then equal mean of contributing courses per PO'
      ],
      ['Included courses', '$included'],
      ['PO', 'Contribution %', 'Contributing courses'],
      for (final po in poCourses.entries)
        [
          po.key,
          (po.value.reduce((a, b) => a + b) / po.value.length)
              .toStringAsFixed(2),
          '${po.value.length}'
        ],
      ['Course', 'PO', 'Contribution %', 'Exam count'],
      ...detailRows,
    ];
    return ReportSnapshot(
        jsonEncode([fingerprints, rows, issues]),
        'Program PO aggregation',
        rows,
        issues,
        issues.isEmpty && poCourses.isNotEmpty);
  }

  void _calculate() {
    if (_year.text.trim().isEmpty || _term.text.trim().isEmpty) {
      showError(context, 'Enter the academic year and term.');
      return;
    }
    setState(() {
      _selectedYear = _year.text.trim();
      _selectedTerm = _term.text.trim();
      _report = _load();
    });
  }

  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'Program reports', children: [
        TextField(
            controller: _year,
            decoration: const InputDecoration(labelText: 'Academic year')),
        TextField(
            controller: _term,
            decoration: const InputDecoration(labelText: 'Term')),
        FilledButton(
            onPressed: _calculate,
            child: const Text('Calculate program aggregation')),
        if (_report != null)
          LoadView(
              future: _report!,
              retry: _calculate,
              builder: (report) => ReportPreview(
                  report: report,
                  load: _load,
                  onStale: () => setState(() {
                        _report = _load();
                      }),
                  exporter: const ShareReportExporter())),
      ]);
}
