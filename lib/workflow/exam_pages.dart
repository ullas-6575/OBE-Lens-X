import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import 'models.dart';
import 'repository.dart';
import 'ui.dart';
import 'scan_pages.dart';
import 'report_page.dart';

class ExamPage extends StatefulWidget {
  final WorkflowRepository repository;
  final Course course;
  final Offering offering;
  final Exam exam;
  final BaseOcrService? ocrService;
  const ExamPage(
      {super.key,
      required this.repository,
      required this.course,
      required this.offering,
      required this.exam,
      this.ocrService});
  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  late Exam _exam = widget.exam;
  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: '${widget.course.code} · ${_exam.name}', children: [
        Text(widget.offering.label),
        if (_exam.validate(widget.course) != null)
          Text(_exam.validate(widget.course)!),
        ActionTile(
            'Questions and CO mapping',
            'Maximum marks, required groups and attainment rules',
            Icons.edit_note, () async {
          await openPage(
              context,
              ExamEditor(
                  repository: widget.repository,
                  course: widget.course,
                  exam: _exam,
                  readOnly: widget.course.archived));
          try {
            final exams = await widget.repository.exams(widget.offering.id);
            if (mounted) {
              setState(() => _exam = exams.firstWhere((e) => e.id == _exam.id));
            }
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        }),
        if (!widget.course.archived)
          FilledButton.icon(
              icon: const Icon(Icons.document_scanner),
              label: const Text('Student / script details'),
              onPressed: _exam.validate(widget.course) != null
                  ? null
                  : () async {
                      final input = await inputDialog(context,
                          'Student / script details', ['Student roll number']);
                      if (!context.mounted || input == null) return;
                      await openPage(
                          context,
                          StudentScanPage(
                              repository: widget.repository,
                              scan: ScanContext(widget.course, widget.offering,
                                  _exam, input[0]),
                              ocrService: widget.ocrService));
                    }),
        ActionTile(
            'All results',
            'Completeness, student details and saved-mark corrections',
            Icons.table_rows,
            () => openPage(
                context,
                ExamResultsPage(
                    repository: widget.repository,
                    course: widget.course,
                    offering: widget.offering,
                    exam: _exam))),
        ActionTile(
            'Calculate attainment',
            'CO attainment → course PO contribution → export',
            Icons.analytics,
            () => openPage(
                context,
                ReportPage(
                    repository: widget.repository,
                    course: widget.course,
                    offering: widget.offering,
                    exam: _exam))),
      ]);
}

class ExamEditor extends StatefulWidget {
  final WorkflowRepository repository;
  final Course course;
  final Exam exam;
  final bool readOnly;
  const ExamEditor(
      {super.key,
      required this.repository,
      required this.course,
      required this.exam,
      this.readOnly = false});
  @override
  State<ExamEditor> createState() => _ExamEditorState();
}

class _ExamEditorState extends State<ExamEditor> {
  late final _name = TextEditingController(text: widget.exam.name);
  late final _threshold =
      TextEditingController(text: widget.exam.policy.scoreThreshold.toString());
  late final _target =
      TextEditingController(text: widget.exam.policy.targetPercent.toString());
  late final _questions = [...widget.exam.questions];
  late final _groups = {...widget.exam.requiredGroups};
  late bool _excludeIncomplete = widget.exam.policy.excludeIncomplete;
  late bool _excludeNA = widget.exam.policy.excludeNA;
  bool _busy = false;
  bool get _disabled => _busy || widget.readOnly;
  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _question([int? index]) async {
    final old = index == null ? null : _questions[index];
    final input = await inputDialog(context, 'Question mapping', [
      'Question (1–8)',
      'Part (a–g)',
      'Maximum marks (1–99)',
      'CO code'
    ], initial: [
      old?.question ?? '1',
      old?.part ?? 'a',
      old?.maxMark.toString() ?? '10',
      old?.co ?? 'CO1'
    ]);
    if (!mounted || input == null) return;
    final maximum = int.tryParse(input[2]);
    if (!RegExp(r'^[1-8]$').hasMatch(input[0]) ||
        !RegExp(r'^[a-g]$').hasMatch(input[1]) ||
        maximum == null ||
        maximum < 1 ||
        maximum > 99 ||
        !widget.course.outcomes.any((c) => c.code == input[3]) ||
        _questions.indexed.any(
            (e) => e.$1 != index && e.$2.key == '${input[0]}:${input[1]}')) {
      showError(context,
          'Use a unique question part, a maximum from 1–99, and a CO defined for this course.');
      return;
    }
    setState(() {
      final q = QuestionMapping(input[0], input[1], input[3], maximum,
          optional: old?.optional ?? false);
      if (index == null) {
        _questions.add(q);
      } else {
        _questions[index] = q;
      }
      _groups.add(q.group);
    });
  }

  Future<void> _save() async {
    final threshold = double.tryParse(_threshold.text),
        target = double.tryParse(_target.text);
    if (_name.text.trim().isEmpty ||
        threshold == null ||
        target == null ||
        !threshold.isFinite ||
        !target.isFinite ||
        threshold < 0 ||
        threshold > 100 ||
        target < 0 ||
        target > 100) {
      showError(
          context, 'Enter an exam name and percentages between 0 and 100.');
      return;
    }
    final exam = Exam(
        id: widget.exam.id,
        offeringId: widget.exam.offeringId,
        name: _name.text.trim(),
        questions: _questions,
        requiredGroups: _groups.toList()..sort(),
        revision: widget.exam.revision,
        policy: AttainmentPolicy(
            scoreThreshold: threshold,
            targetPercent: target,
            excludeIncomplete: _excludeIncomplete,
            excludeNA: _excludeNA));
    final error = exam.validate(widget.course);
    if (error != null) {
      showError(context, error);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.saveExam(exam);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'Questions, marks and CO mapping', children: [
        TextFormField(
            controller: _name,
            enabled: !_disabled,
            decoration: const InputDecoration(labelText: 'Exam name')),
        Text(
            'Available outcomes: ${widget.course.outcomes.map((c) => c.code).join(', ')}'),
        const Text(
            'Configure only the rubric cells used in this exam. Unmapped cells must remain N/A.'),
        Wrap(spacing: 12, children: [
          for (final group in ['1-4', '5-8'])
            FilterChip(
                label: Text('Required group Q$group'),
                selected: _groups.contains(group),
                onSelected: _disabled
                    ? null
                    : (v) => setState(() {
                          if (v) {
                            _groups.add(group);
                          } else {
                            _groups.remove(group);
                          }
                        }))
        ]),
        for (var i = 0; i < _questions.length; i++)
          Card(
              child: Column(children: [
            ListTile(
                title: Text(
                    'Q${_questions[i].question}${_questions[i].part} · ${_questions[i].maxMark} marks → ${_questions[i].co}'),
                onTap: _disabled ? null : () => _question(i),
                trailing: IconButton(
                    tooltip: 'Remove mapping',
                    icon: const Icon(Icons.close),
                    onPressed: _disabled
                        ? null
                        : () => setState(() => _questions.removeAt(i)))),
            CheckboxListTile(
                title: const Text('Optional: exclude when N/A'),
                value: _questions[i].optional,
                onChanged: _disabled
                    ? null
                    : (v) => setState(() {
                          final q = _questions[i];
                          _questions[i] = QuestionMapping(
                              q.question, q.part, q.co, q.maxMark,
                              optional: v!);
                        })),
          ])),
        OutlinedButton(
            onPressed: _disabled ? null : () => _question(),
            child: const Text('Add question part')),
        const Divider(),
        Text('Attainment policy',
            style: Theme.of(context).textTheme.titleLarge),
        TextFormField(
            controller: _threshold,
            enabled: !_disabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Student score threshold (%)')),
        TextFormField(
            controller: _target,
            enabled: !_disabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Target percentage of eligible students (%)')),
        SwitchListTile(
            title: const Text('Exclude incomplete scripts'),
            subtitle:
                const Text('When off, incomplete scripts block report export.'),
            value: _excludeIncomplete,
            onChanged: _disabled
                ? null
                : (v) => setState(() => _excludeIncomplete = v)),
        SwitchListTile(
            title: const Text('Exclude N/A from the denominator'),
            subtitle: const Text(
                'When off, required N/A cells count as zero. Optional N/A cells are always excluded.'),
            value: _excludeNA,
            onChanged:
                _disabled ? null : (v) => setState(() => _excludeNA = v)),
        const Text(
            'CO attainment = eligible students meeting the score threshold ÷ eligible students. PO contribution = equal mean of linked CO percentages. All-optional or excluded cells with no possible marks are ineligible.'),
        if (!widget.readOnly)
          FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save exam configuration')),
      ]);
}
