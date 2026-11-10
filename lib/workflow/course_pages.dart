import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import 'models.dart';
import 'repository.dart';
import 'ui.dart';
import 'exam_pages.dart';

class CourseListPage extends StatefulWidget {
  final WorkflowRepository repository;
  final bool isAdmin;
  final BaseOcrService? ocrService;
  const CourseListPage(
      {super.key,
      required this.repository,
      required this.isAdmin,
      this.ocrService});
  @override
  State<CourseListPage> createState() => _CourseListPageState();
}

class _CourseListPageState extends State<CourseListPage> {
  late Future<List<Course>> _courses = widget.repository.courses();
  void _reload() => setState(() {
        _courses = widget.repository.courses();
      });
  @override
  Widget build(BuildContext context) => WorkflowPage(
          title: widget.isAdmin ? 'Manage courses' : 'Assigned courses',
          children: [
            if (widget.isAdmin)
              FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add course'),
                  onPressed: () async {
                    await openPage(
                        context, CourseEditor(repository: widget.repository));
                    if (mounted) _reload();
                  }),
            LoadView(
                future: _courses,
                retry: _reload,
                builder: (courses) => Column(children: [
                      if (courses.isEmpty)
                        const Text(
                            'No courses available. An admin must create an offering and assign a teacher.'),
                      for (final course in courses)
                        ActionTile(
                            '${course.code} · ${course.title}',
                            course.archived
                                ? 'Archived · historical results'
                                : '${course.outcomes.length} course outcomes',
                            Icons.menu_book, () async {
                          await openPage(
                              context,
                              CoursePage(
                                  repository: widget.repository,
                                  course: course,
                                  isAdmin: widget.isAdmin,
                                  ocrService: widget.ocrService));
                          if (mounted) _reload();
                        }),
                    ]))
          ]);
}

class CourseEditor extends StatefulWidget {
  final WorkflowRepository repository;
  final Course? course;
  const CourseEditor({super.key, required this.repository, this.course});
  @override
  State<CourseEditor> createState() => _CourseEditorState();
}

class _CourseEditorState extends State<CourseEditor> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.course?.code);
  late final _title = TextEditingController(text: widget.course?.title);
  late final List<CourseOutcome> _outcomes = [
    for (var number = 1; number <= 4; number++)
      widget.course?.outcomes.firstWhere(
            (outcome) => outcome.code == 'CO$number',
            orElse: () => CourseOutcome('CO$number', 'CO$number', const []),
          ) ??
          CourseOutcome('CO$number', 'CO$number', const []),
  ];
  late final bool _archived = widget.course?.archived ?? false;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.saveCourse(
          id: widget.course?.id,
          code: _code.text,
          title: _title.text,
          outcomes: _outcomes,
          archived: _archived);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'Course configuration', children: [
        Form(
            key: _form,
            child: Column(children: [
              TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'Course code'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null),
              TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Course title'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null),
            ])),
        Text('Course outcomes and CO–PO mapping',
            style: Theme.of(context).textTheme.titleLarge),
        const Text(
            'Select each PO linked to a CO. Reports treat checked links equally; they do not imply numeric weights.'),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(horizontalMargin: 12, columnSpacing: 12, columns: [
              const DataColumn(label: Text('Course Outcomes')),
              for (var p = 1; p <= 12; p++) DataColumn(label: Text('PO$p')),
            ], rows: [
              for (var number = 1; number <= 4; number++) _outcomeRow(number),
            ])),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save course')),
      ]);

  DataRow _outcomeRow(int number) {
    final code = 'CO$number';
    final index = _outcomes.indexWhere((outcome) => outcome.code == code);
    final outcome = _outcomes[index];
    return DataRow(cells: [
      DataCell(Text(code)),
      for (var p = 1; p <= 12; p++)
        DataCell(Checkbox(
            value: outcome.pos.contains('PO$p'),
            onChanged: _busy
                ? null
                : (selected) => setState(() {
                      final pos = [...outcome.pos];
                      if (selected == true) {
                        pos.add('PO$p');
                      } else {
                        pos.remove('PO$p');
                      }
                      _outcomes[index] =
                          CourseOutcome(code, outcome.description, pos);
                    }))),
    ]);
  }
}

class CoursePage extends StatefulWidget {
  final WorkflowRepository repository;
  final Course course;
  final bool isAdmin;
  final BaseOcrService? ocrService;
  const CoursePage(
      {super.key,
      required this.repository,
      required this.course,
      required this.isAdmin,
      this.ocrService});
  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  late Course _course = widget.course;
  late Future<List<Offering>> _offerings =
      widget.repository.offerings(_course.id);
  bool _busy = false;
  void _reload() => setState(() {
        _offerings = widget.repository.offerings(_course.id);
      });

  Future<List<String>?> _newOfferingDetails() {
    var selectedYear = '1';
    var selectedTerm = '1';
    return showDialog<List<String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title: const Text('New offering'),
                    content: SizedBox(
                        width: 440,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButtonFormField<String>(
                              value: selectedYear,
                              decoration:
                                  const InputDecoration(labelText: 'Year'),
                              items: [
                                for (var year = 1; year <= 4; year++)
                                  DropdownMenuItem(
                                      value: '$year', child: Text('$year')),
                              ],
                              onChanged: (value) =>
                                  setDialogState(() => selectedYear = value!)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              value: selectedTerm,
                              decoration:
                                  const InputDecoration(labelText: 'Term'),
                              items: [
                                for (var term = 1; term <= 2; term++)
                                  DropdownMenuItem(
                                      value: '$term', child: Text('$term')),
                              ],
                              onChanged: (value) =>
                                  setDialogState(() => selectedTerm = value!)),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(
                              dialogContext, [selectedYear, selectedTerm]),
                          child: const Text('Continue')),
                    ])));
  }

  Future<void> _deleteCourse() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Delete course?'),
                content: const Text(
                    'A course can be deleted only when it has no offerings. Courses with offerings cannot be deleted because they have linked exam and result history.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete course')),
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.deleteCourse(_course.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: '${_course.code} · Offerings', children: [
        Text(_course.title),
        if (widget.isAdmin)
          OutlinedButton(
              onPressed: _busy ? null : _deleteCourse,
              child: const Text('Delete course')),
        if (widget.isAdmin)
          OutlinedButton(
              onPressed: () async {
                final changed = await openPage<bool>(
                    context,
                    CourseEditor(
                        repository: widget.repository, course: _course));
                if (changed == true) {
                  try {
                    final courses = await widget.repository.courses();
                    if (mounted) {
                      setState(() => _course =
                          courses.firstWhere((c) => c.id == _course.id));
                    }
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                }
              },
              child: const Text('Edit course and CO–PO mapping')),
        if (widget.isAdmin && !_course.archived)
          FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final values = await _newOfferingDetails();
                      if (values == null || !mounted) return;
                      setState(() => _busy = true);
                      try {
                        await widget.repository
                            .addOffering(_course.id, values[0], values[1]);
                        _reload();
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('Add year / term offering')),
        LoadView(
            future: _offerings,
            retry: _reload,
            builder: (offerings) => Column(children: [
                  if (offerings.isEmpty)
                    const Text('No offerings assigned or configured.'),
                  for (final offering in offerings)
                    Card(
                        child: Column(children: [
                      ListTile(
                          title: Text(offering.label),
                          subtitle: const Text('Exams and results'),
                          leading: const Icon(Icons.calendar_month),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => openPage(
                              context,
                              OfferingPage(
                                  repository: widget.repository,
                                  course: _course,
                                  offering: offering,
                                  isAdmin: widget.isAdmin,
                                  ocrService: widget.ocrService))),
                      if (widget.isAdmin)
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                                onPressed: () => openPage(
                                    context,
                                    AssignmentPage(
                                        repository: widget.repository,
                                        offering: offering)),
                                icon: const Icon(Icons.person_add),
                                label: const Text('Assign teachers'))),
                    ])),
                ]))
      ]);
}

class OfferingPage extends StatefulWidget {
  final WorkflowRepository repository;
  final Course course;
  final Offering offering;
  final bool isAdmin;
  final BaseOcrService? ocrService;
  const OfferingPage(
      {super.key,
      required this.repository,
      required this.course,
      required this.offering,
      required this.isAdmin,
      this.ocrService});
  @override
  State<OfferingPage> createState() => _OfferingPageState();
}

class _OfferingPageState extends State<OfferingPage> {
  late Future<List<Exam>> _exams = widget.repository.exams(widget.offering.id);
  void _reload() => setState(() {
        _exams = widget.repository.exams(widget.offering.id);
      });
  @override
  Widget build(BuildContext context) => WorkflowPage(
          title: '${widget.course.code} · ${widget.offering.label}',
          children: [
            if (!widget.course.archived)
              FilledButton(
                  onPressed: () async {
                    await openPage(
                        context,
                        ExamEditor(
                            repository: widget.repository,
                            course: widget.course,
                            exam: Exam(
                                id: '',
                                offeringId: widget.offering.id,
                                name: '')));
                    if (mounted) _reload();
                  },
                  child: const Text('Add exam')),
            LoadView(
                future: _exams,
                retry: _reload,
                builder: (exams) => Column(children: [
                      if (exams.isEmpty)
                        const Text(
                            'Create an exam, then configure its questions and CO mappings.'),
                      for (final exam in exams)
                        ActionTile(
                            exam.name,
                            '${exam.questions.length} mapped question parts',
                            Icons.assignment, () async {
                          await openPage(
                              context,
                              ExamPage(
                                  repository: widget.repository,
                                  course: widget.course,
                                  offering: widget.offering,
                                  exam: exam,
                                  ocrService: widget.ocrService));
                          if (mounted) _reload();
                        }),
                    ]))
          ]);
}

class AssignmentPage extends StatefulWidget {
  final WorkflowRepository repository;
  final Offering offering;
  const AssignmentPage(
      {super.key, required this.repository, required this.offering});
  @override
  State<AssignmentPage> createState() => _AssignmentPageState();
}

class _AssignmentPageState extends State<AssignmentPage> {
  late Future<(List<Json>, List<String>)> _data = _load();
  bool _busy = false;
  Future<(List<Json>, List<String>)> _load() async => (
        await widget.repository.teachers(),
        await widget.repository.assignments(widget.offering.id)
      );
  @override
  Widget build(BuildContext context) => WorkflowPage(
          title: 'Assign teachers · ${widget.offering.label}',
          children: [
            LoadView(
                future: _data,
                retry: () => setState(() {
                      _data = _load();
                    }),
                builder: (data) => Column(children: [
                      for (final teacher in data.$1)
                        CheckboxListTile(
                            title: Text(teacher['full_name']),
                            subtitle: Text(
                                '${teacher['email']}${teacher['approved'] == true ? '' : ' · awaiting approval'}'),
                            value: data.$2.contains(teacher['id']),
                            onChanged: _busy ||
                                    (teacher['approved'] != true &&
                                        !data.$2.contains(teacher['id']))
                                ? null
                                : (v) async {
                                    setState(() => _busy = true);
                                    try {
                                      await widget.repository.assign(
                                          widget.offering.id,
                                          teacher['id'],
                                          v!);
                                      if (mounted) {
                                        setState(() {
                                          _data = _load();
                                        });
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        showError(context, e);
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  }),
                    ]))
          ]);
}
