import 'dart:math';
import 'package:flutter/material.dart';
import '../models/marks_table_data.dart';
import '../models/scan_workflow.dart';
import '../screens/image_source_screen.dart';
import '../screens/verification_screen.dart';
import '../services/ocr_service.dart';
import 'models.dart';
import 'repository.dart';
import 'ui.dart';
import 'report_page.dart';

String newSubmissionId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class StudentScanPage extends StatefulWidget {
  final WorkflowRepository repository;
  final ScanContext scan;
  final BaseOcrService? ocrService;
  const StudentScanPage(
      {super.key,
      required this.repository,
      required this.scan,
      this.ocrService});
  @override
  State<StudentScanPage> createState() => _StudentScanPageState();
}

class _StudentScanPageState extends State<StudentScanPage> {
  Future<void> _nextStudent() async {
    final values = await inputDialog(
        context, 'Student / script details', ['Student roll number']);
    if (!mounted || values == null) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => StudentScanPage(
            repository: widget.repository,
            ocrService: widget.ocrService,
            scan: ScanContext(widget.scan.course, widget.scan.offering,
                widget.scan.exam, values.first))));
  }

  late Future<List<Json>> _results =
      widget.repository.results(widget.scan.exam.id);
  void _reload() => setState(() {
        _results = widget.repository.results(widget.scan.exam.id);
      });
  Future<void> _scan(List<String> remaining) async {
    final route = ModalRoute.of(context);
    await openPage(
        context,
        ImageSourceScreen(
            ocrService: widget.ocrService,
            workflow: ScanWorkflow(
                rollNo: widget.scan.rollNo,
                description: widget.scan.label,
                groups: remaining,
                validate: widget.scan.validateMarks,
                review: (data) async {
                  final next = await openPage<String>(
                      context,
                      SubmissionPage(
                          repository: widget.repository,
                          scan: widget.scan,
                          data: data));
                  if (!mounted || next == null) return;
                  Navigator.of(context).popUntil((r) => r == route);
                  _reload();
                  if (next == 'next') {
                    await _nextStudent();
                    return;
                  }
                  if (next == 'results') {
                    await openPage(
                        context,
                        ExamResultsPage(
                            repository: widget.repository,
                            course: widget.scan.course,
                            offering: widget.scan.offering,
                            exam: widget.scan.exam));
                  }
                })));
  }

  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'Student ${widget.scan.rollNo}', children: [
        Text(widget.scan.label),
        LoadView(
            future: _results,
            retry: _reload,
            builder: (results) {
              final saved = results
                  .where((r) => r['roll_no'] == widget.scan.rollNo)
                  .map((r) => r['table_type'])
                  .toSet();
              final remaining = widget.scan.exam.requiredGroups
                  .where((g) => !saved.contains(g))
                  .toList();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final group in widget.scan.exam.requiredGroups)
                      ListTile(
                          title: Text('Questions $group'),
                          subtitle: Text(saved.contains(group)
                              ? 'Saved'
                              : 'Missing group'),
                          leading: Icon(saved.contains(group)
                              ? Icons.check_circle
                              : Icons.pending_outlined)),
                    if (remaining.isNotEmpty)
                      FilledButton(
                          onPressed: () => _scan(remaining),
                          child: const Text('Choose group and scan')),
                    if (remaining.isEmpty)
                      const Text(
                          'All required groups are saved. Use results to correct saved marks.'),
                    OutlinedButton(
                        onPressed: _nextStudent,
                        child: const Text('Next student')),
                    TextButton(
                        onPressed: () async {
                          await openPage(
                              context,
                              ExamResultsPage(
                                  repository: widget.repository,
                                  course: widget.scan.course,
                                  offering: widget.scan.offering,
                                  exam: widget.scan.exam));
                          if (mounted) _reload();
                        },
                        child: const Text('All results')),
                  ]);
            })
      ]);
}

class SubmissionPage extends StatefulWidget {
  final WorkflowRepository repository;
  final ScanContext scan;
  final MarksTableData data;
  final Json? previous;
  const SubmissionPage(
      {super.key,
      required this.repository,
      required this.scan,
      required this.data,
      this.previous});
  @override
  State<SubmissionPage> createState() => _SubmissionPageState();
}

class _SubmissionPageState extends State<SubmissionPage> {
  late final String _submissionId = newSubmissionId();
  bool _busy = false, _saved = false;
  String? _error;
  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveMarks(widget.scan, _submissionId,
          widget.data.tableType, widget.data.cellMarks,
          resultId: widget.previous?['id'],
          revision: widget.previous?['revision']);
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = 'Could not save: $e. Your reviewed marks are still here.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy && !_saved,
      child: WorkflowPage(
          title: _saved ? 'Result saved' : 'Submission summary',
          children: [
            Text(widget.scan.label),
            Text('Group: Q${widget.data.tableType}'),
            if (widget.previous != null)
              Text(
                  'Revision ${widget.previous!['revision']} → ${(widget.previous!['revision'] as int) + 1}'),
            for (final q in widget.data.questions)
              ListTile(
                  title: Text('Question $q'),
                  subtitle: Text(widget.data.cellMarks[q]!.entries
                      .map((e) => '${e.key}: ${e.value}')
                      .join(' · ')),
                  trailing: Text(
                      widget.data.calculateColumnTotal(q).toStringAsFixed(0))),
            Text('Total: ${widget.data.grandTotal.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.headlineSmall),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (!_saved)
              FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy
                      ? 'Saving…'
                      : _error == null
                          ? 'Save result'
                          : 'Retry save')),
            if (!_saved)
              TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Back to verification')),
            if (_saved && widget.previous == null) ...[
              FilledButton(
                  onPressed: () => Navigator.pop(context, 'remaining'),
                  child: const Text('Check / scan missing group')),
              OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'next'),
                  child: const Text('Next student')),
            ],
            if (_saved)
              FilledButton(
                  onPressed: () => Navigator.pop(context, 'results'),
                  child: const Text('All results')),
          ]));
}

class ExamResultsPage extends StatefulWidget {
  final WorkflowRepository repository;
  final Course course;
  final Offering offering;
  final Exam exam;
  const ExamResultsPage(
      {super.key,
      required this.repository,
      required this.course,
      required this.offering,
      required this.exam});
  @override
  State<ExamResultsPage> createState() => _ExamResultsPageState();
}

class _ExamResultsPageState extends State<ExamResultsPage> {
  late Future<List<Json>> _results = widget.repository.results(widget.exam.id);
  void _reload() => setState(() {
        _results = widget.repository.results(widget.exam.id);
      });
  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'All results · ${widget.exam.name}', actions: [
        IconButton(
            onPressed: _reload,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh))
      ], children: [
        Text('${widget.course.code} · ${widget.offering.label}'),
        ActionTile(
            'Calculate attainment',
            'Check completeness and preview CO / PO reports',
            Icons.analytics,
            () => openPage(
                context,
                ReportPage(
                    repository: widget.repository,
                    course: widget.course,
                    offering: widget.offering,
                    exam: widget.exam))),
        LoadView(
            future: _results,
            retry: _reload,
            builder: (rows) {
              final students = <String, List<Json>>{};
              for (final row in rows) {
                students.putIfAbsent(row['roll_no'], () => []).add(row);
              }
              final rolls = students.keys.toList()..sort();
              return Column(children: [
                if (rows.isEmpty) const Text('No saved results for this exam.'),
                for (final roll in rolls)
                  ActionTile(
                      roll,
                      '${students[roll]!.length}/${widget.exam.requiredGroups.length} groups · Total ${students[roll]!.fold<double>(0, (v, r) => v + (r['grand_total'] as num).toDouble()).toStringAsFixed(0)}',
                      Icons.person, () async {
                    await openPage(
                        context,
                        StudentResultPage(
                            repository: widget.repository,
                            scan: ScanContext(widget.course, widget.offering,
                                widget.exam, roll),
                            results: students[roll]!));
                    if (mounted) _reload();
                  }),
              ]);
            })
      ]);
}

class StudentResultPage extends StatelessWidget {
  final WorkflowRepository repository;
  final ScanContext scan;
  final List<Json> results;
  const StudentResultPage(
      {super.key,
      required this.repository,
      required this.scan,
      required this.results});
  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'Result details · ${scan.rollNo}', children: [
        Text(scan.label),
        for (final group in scan.exam.requiredGroups)
          if (!results.any((r) => r['table_type'] == group))
            Text('Missing group Q$group'),
        for (final result in results)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            'Q${result['table_type']} · revision ${result['revision']} · total ${result['grand_total']}'),
                        for (final q in (result['marks'] as Map).entries)
                          Text(
                              'Q${q.key}: ${(q.value as Map).entries.map((e) => '${e.key}: ${e.value}').join(', ')}'),
                        if (!scan.course.archived)
                          TextButton(
                              onPressed: () async {
                                final route = ModalRoute.of(context);
                                final marks = (result['marks'] as Map).map(
                                    (q, c) => MapEntry(
                                        q.toString(),
                                        (c as Map).map((p, v) => MapEntry(
                                            p.toString(), v.toString()))));
                                await openPage(
                                    context,
                                    VerificationScreen(
                                        marksTableData: MarksTableData(
                                            tableType: result['table_type'],
                                            cellMarks: marks),
                                        workflow: ScanWorkflow(
                                            rollNo: scan.rollNo,
                                            description: scan.label,
                                            groups: [result['table_type']],
                                            validate: scan.validateMarks,
                                            review: (data) async {
                                              final next =
                                                  await openPage<String>(
                                                      context,
                                                      SubmissionPage(
                                                          repository:
                                                              repository,
                                                          scan: scan,
                                                          data: data,
                                                          previous: result));
                                              if (context.mounted &&
                                                  next != null) {
                                                Navigator.of(context).popUntil(
                                                    (r) => r == route);
                                                Navigator.pop(
                                                    context); // Results list reloads the saved revision.
                                              }
                                            })));
                              },
                              child: const Text('Correct saved marks')),
                      ]))),
      ]);
}
