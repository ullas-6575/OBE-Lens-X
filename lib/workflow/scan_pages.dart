import 'dart:math';
import 'package:flutter/material.dart';
import '../models/marks_table_data.dart';
import '../models/scan_workflow.dart';
import '../screens/image_source_screen.dart';
import '../screens/verification_screen.dart';
import '../services/ocr_service.dart';
import '../widgets/marks_grid_table.dart';
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
  bool _started = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    if (_started || !mounted) return;
    _started = true;
    try {
      final results = await widget.repository.results(widget.scan.exam.id);
      if (!mounted) return;
      final saved = results
          .where((r) => r['roll_no'] == widget.scan.rollNo)
          .map((r) => r['table_type'])
          .toSet();
      final remaining = widget.scan.exam.requiredGroups
          .where((group) => !saved.contains(group))
          .toList();
      if (remaining.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'All required groups are already scanned. Use All results to view or correct marks.')));
        Navigator.of(context).pop();
        return;
      }
      await _scan(remaining);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load scan status: $error');
      }
    }
  }

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

  Future<void> _scan(List<String> remaining) async {
    final route = ModalRoute.of(context);
    var handled = false;
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
                          data: data,
                          remainingGroups: remaining
                              .where((group) => group != data.tableType)
                              .toList()));
                  if (!mounted || next == null) return;
                  handled = true;
                  Navigator.of(context).popUntil((r) => r == route);
                  if (next == 'remaining') {
                    final nextGroups = remaining
                        .where((group) => group != data.tableType)
                        .toList();
                    if (nextGroups.isNotEmpty) await _scan(nextGroups);
                    return;
                  }
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
    if (mounted && !handled) {
      setState(() => _error = 'Scan cancelled. Tap Scan to try again.');
    }
  }

  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'Student ${widget.scan.rollNo}', children: [
        Text(widget.scan.label),
        if (_error == null)
          const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()))
        else ...[
          Text(_error!),
          FilledButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _started = false;
                });
                _startScan();
              },
              child: const Text('Scan')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back')),
        ],
      ]);
}

class SubmissionPage extends StatefulWidget {
  final WorkflowRepository repository;
  final ScanContext scan;
  final MarksTableData data;
  final Json? previous;
  final List<String> remainingGroups;
  const SubmissionPage(
      {super.key,
      required this.repository,
      required this.scan,
      required this.data,
      this.previous,
      this.remainingGroups = const []});
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
            MarksGridTable(marks: widget.data.cellMarks),
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
              if (widget.remainingGroups.isNotEmpty)
                FilledButton(
                    onPressed: () => Navigator.pop(context, 'remaining'),
                    child: const Text('Scan next group'))
              else
                FilledButton(
                    onPressed: () => Navigator.pop(context, 'next'),
                    child: const Text('Next student')),
            ],
            if (_saved && widget.previous != null)
              FilledButton(
                  onPressed: () => Navigator.pop(context, 'results'),
                  child: const Text('Back to results')),
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

  Map<String, Map<String, String>> _marks(Json result) =>
      (result['marks'] as Map).map((question, cells) => MapEntry(
          question.toString(),
          (cells as Map).map(
              (part, value) => MapEntry(part.toString(), value.toString()))));

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
                        MarksGridTable(marks: _marks(result)),
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
