import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              label: const Text('Scan'),
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
            'Completeness and student result details',
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
  final Map<String, TextEditingController> _maxMarkControllers = {};
  final Map<String, String> _cellOutcomes = {};
  late final _groups = <String>{
    if (widget.exam.id.isNotEmpty) ...widget.exam.requiredGroups,
  };
  bool _busy = false;
  bool get _disabled => _busy || widget.readOnly;

  @override
  void initState() {
    super.initState();
    for (final group in _groups) {
      _initializeGroupCells(group);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    _target.dispose();
    for (final controller in _maxMarkControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _questionsInGroup(String group) =>
      group == '1-4' ? ['1', '2', '3', '4'] : ['5', '6', '7', '8'];

  String _cellKey(String question, String part) => '$question:$part';

  void _initializeGroupCells(String group) {
    for (final question in _questionsInGroup(group)) {
      for (final part in 'abcdefg'.split('')) {
        final key = _cellKey(question, part);
        QuestionMapping? existing;
        for (final mapping in widget.exam.questions) {
          if (mapping.question == question && mapping.part == part) {
            existing = mapping;
            break;
          }
        }
        _maxMarkControllers.putIfAbsent(
            key,
            () => TextEditingController(
                text: existing?.maxMark.toString() ?? '0'));
        _cellOutcomes[key] = existing?.co ?? CourseOutcome.codes.first;
      }
    }
  }

  void _toggleGroup(String group, bool selected) {
    setState(() {
      if (selected) {
        _groups.add(group);
        _initializeGroupCells(group);
      } else {
        _groups.remove(group);
        for (final question in _questionsInGroup(group)) {
          for (final part in 'abcdefg'.split('')) {
            final key = _cellKey(question, part);
            _maxMarkControllers.remove(key)?.dispose();
            _cellOutcomes.remove(key);
          }
        }
      }
    });
  }

  List<QuestionMapping>? _buildMappings() {
    final mappings = <QuestionMapping>[];
    for (final group in _groups) {
      for (final question in _questionsInGroup(group)) {
        for (final part in 'abcdefg'.split('')) {
          final key = _cellKey(question, part);
          final text = _maxMarkControllers[key]?.text.trim() ?? '0';
          final maximum = int.tryParse(text);
          if (maximum == null || maximum < 0 || maximum > 99) {
            showError(context,
                'Q$question$part must have a maximum from 0 to 99. Use 0 when that part does not exist.');
            return null;
          }
          if (maximum == 0) continue;
          final co = _cellOutcomes[key];
          if (co == null || !CourseOutcome.codes.contains(co)) {
            showError(context, 'Choose a course outcome for Q$question$part.');
            return null;
          }
          mappings.add(QuestionMapping(question, part, co, maximum));
        }
      }
    }
    return mappings;
  }

  Widget _maximumCell(String question, String part) {
    final key = _cellKey(question, part);
    return SizedBox(
        width: 76,
        child: TextField(
            controller: _maxMarkControllers[key],
            enabled: !_disabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 2,
            decoration: const InputDecoration(
                labelText: 'Max mark',
                isDense: true,
                counterText: '',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8))));
  }

  Widget _outcomeCell(String question, String part) {
    final key = _cellKey(question, part);
    const outcomes = CourseOutcome.codes;
    final selectedOutcome = _cellOutcomes[key];
    return SizedBox(
        width: 88,
        child: DropdownButtonFormField<String>(
            value: outcomes.contains(selectedOutcome) ? selectedOutcome : null,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'CO',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
            items: [
              for (final outcome in outcomes)
                DropdownMenuItem(value: outcome, child: Text(outcome)),
            ],
            onChanged: _disabled
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _cellOutcomes[key] = value);
                  }));
  }

  Widget _questionMatrix(
      String group, String title, Widget Function(String, String) cellBuilder) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
              horizontalMargin: 8,
              columnSpacing: 8,
              dataRowMinHeight: 56,
              dataRowMaxHeight: 64,
              columns: [
                const DataColumn(label: Text('Question')),
                for (final part in 'abcdefg'.split(''))
                  DataColumn(label: Text(part)),
              ],
              rows: [
                for (final question in _questionsInGroup(group))
                  DataRow(cells: [
                    DataCell(Text('Q$question')),
                    for (final part in 'abcdefg'.split(''))
                      DataCell(cellBuilder(question, part)),
                  ]),
              ])),
    ]);
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
    final mappings = _buildMappings();
    if (mappings == null) return;
    final exam = Exam(
        id: widget.exam.id,
        offeringId: widget.exam.offeringId,
        name: _name.text.trim(),
        questions: mappings,
        requiredGroups: _groups.toList()..sort(),
        revision: widget.exam.revision,
        policy:
            AttainmentPolicy(scoreThreshold: threshold, targetPercent: target));
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
        const Text(
            'Select a question group to configure its questions. Enter the maximum mark and course outcome for each part a–g. Leave the maximum at 0 when that part does not exist.'),
        Wrap(spacing: 12, children: [
          for (final group in ['1-4', '5-8'])
            FilterChip(
                label: Text('Questions $group · all parts'),
                selected: _groups.contains(group),
                onSelected:
                    _disabled ? null : (value) => _toggleGroup(group, value))
        ]),
        for (final group in ['1-4', '5-8'])
          if (_groups.contains(group)) ...[
            _questionMatrix(
                group, 'Questions $group · maximum marks', _maximumCell),
            _questionMatrix(
                group, 'Questions $group · course outcomes', _outcomeCell),
          ],
        const Divider(),
        Text('Attainment thresholds and target',
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
        const Text(
            'CO attainment = eligible students meeting the score threshold ÷ eligible students. PO contribution = equal mean of linked CO percentages. N/A marks count as zero.'),
        if (!widget.readOnly)
          FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save exam configuration')),
      ]);
}
