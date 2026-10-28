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
  late final List<CourseOutcome> _outcomes = [...?widget.course?.outcomes];
  late bool _archived = widget.course?.archived ?? false;
  bool _busy = false;
  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _outcome([int? index]) async {
    final old = index == null ? null : _outcomes[index];
    final values = await inputDialog(context, 'Course outcome', [
      'CO code (e.g. CO1)',
      'Description'
    ], initial: [
      old?.code ?? 'CO${_outcomes.length + 1}',
      old?.description ?? ''
    ]);
    if (!mounted || values == null) return;
    if (!RegExp(r'^CO[1-9][0-9]*$').hasMatch(values[0]) ||
        _outcomes.indexed.any((e) => e.$1 != index && e.$2.code == values[0])) {
      showError(context, 'Use a unique CO code, such as CO1.');
      return;
    }
    setState(() {
      final outcome = CourseOutcome(values[0], values[1], old?.pos ?? []);
      if (index == null) {
        _outcomes.add(outcome);
      } else {
        _outcomes[index] = outcome;
      }
    });
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
        SwitchListTile(
            title: const Text('Archive course'),
            subtitle: const Text('Preserve history and stop new scans'),
            value: _archived,
            onChanged: _busy ? null : (v) => setState(() => _archived = v)),
        Text('Course outcomes and CO–PO links',
            style: Theme.of(context).textTheme.titleLarge),
        const Text(
            'Checkboxes define relationships. Reports use an equal mean of linked CO percentages; no numeric weights are implied.'),
        for (var i = 0; i < _outcomes.length; i++)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    ListTile(
                        title: Text(
                            '${_outcomes[i].code}: ${_outcomes[i].description}'),
                        onTap: _busy ? null : () => _outcome(i),
                        trailing: IconButton(
                            tooltip: 'Remove outcome',
                            icon: const Icon(Icons.close),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _outcomes.removeAt(i)))),
                    Wrap(spacing: 8, children: [
                      for (var p = 1; p <= 12; p++)
                        FilterChip(
                            label: Text('PO$p'),
                            selected: _outcomes[i].pos.contains('PO$p'),
                            onSelected: _busy
                                ? null
                                : (v) => setState(() {
                                      final co = _outcomes[i];
                                      final pos = [...co.pos];
                                      if (v) {
                                        pos.add('PO$p');
                                      } else {
                                        pos.remove('PO$p');
                                      }
                                      _outcomes[i] = CourseOutcome(
                                          co.code, co.description, pos);
                                    }))
                    ]),
                  ]))),
        OutlinedButton(
            onPressed: _busy ? null : () => _outcome(),
            child: const Text('Add course outcome')),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save course')),
      ]);
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
  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: '${_course.code} · Offerings', children: [
        Text(_course.title),
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
                      final values = await inputDialog(
                          context, 'New offering', ['Academic year', 'Term']);
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
                    ActionTile(
                        offering.label,
                        'Teachers, exams and results',
                        Icons.calendar_month,
                        () => openPage(
                            context,
                            OfferingPage(
                                repository: widget.repository,
                                course: _course,
                                offering: offering,
                                isAdmin: widget.isAdmin,
                                ocrService: widget.ocrService))),
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
            if (widget.isAdmin)
              ActionTile(
                  'Assign teachers',
                  'Approved accounts only',
                  Icons.person_add,
                  () => openPage(
                      context,
                      AssignmentPage(
                          repository: widget.repository,
                          offering: widget.offering))),
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
