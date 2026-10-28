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
      'N/A policy',
      exam.policy.excludeNA
          ? 'Excluded from denominator'
          : 'Required cells count as zero'
    ],
    ['Optional N/A', 'Excluded from denominator'],
    [
      'Incomplete policy',
      exam.policy.excludeIncomplete ? 'Exclude script' : 'Block export'
    ],
    ['Students / excluded', '${report.students} / ${report.excluded}'],
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
    ['Scope', 'This is a course contribution, not program-wide PO attainment.'],
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

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final issue in widget.report.issues)
          Text(issue,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (!widget.report.exportable && widget.report.issues.isEmpty)
          const Text(
              'No eligible results yet. Export becomes available after eligible scripts are saved.'),
        for (final row in widget.report.rows)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(row.join('   |   '))),
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
      [
        'Scope',
        'All visible offerings in this year/term; this project models one program.'
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
