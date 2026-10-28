import 'package:flutter/material.dart';
import '../screens/image_source_screen.dart';
import '../screens/results_screen.dart';
import '../models/scan_workflow.dart';
import '../services/ocr_service.dart';
import 'models.dart';
import 'repository.dart';
import 'ui.dart';
import 'course_pages.dart';
import 'report_page.dart';

class Dashboard extends StatefulWidget {
  final WorkflowRepository repository;
  final bool isAdmin;
  final BaseOcrService? ocrService;
  final Future<void> Function() signOut;
  const Dashboard(
      {super.key,
      required this.repository,
      required this.isAdmin,
      required this.signOut,
      this.ocrService});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late Future<Json> _profile = widget.repository.profile();
  @override
  Widget build(BuildContext context) => WorkflowPage(
          title: widget.isAdmin ? 'Admin dashboard' : 'Teacher dashboard',
          actions: [
            IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  try {
                    await widget.signOut();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                })
          ],
          children: [
            LoadView(
                future: _profile,
                retry: () => setState(() {
                      _profile = widget.repository.profile();
                    }),
                builder: (profile) {
                  if (!widget.isAdmin && profile['approved'] != true) {
                    return Column(children: [
                      const Text('Your account is awaiting teacher approval.'),
                      TextButton(
                          onPressed: () => setState(() {
                                _profile = widget.repository.profile();
                              }),
                          child: const Text('Check approval'))
                    ]);
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Welcome, ${profile['full_name']}',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        ActionTile(
                            widget.isAdmin
                                ? 'Manage courses'
                                : 'Assigned courses',
                            'Course → offering → exam → scan → results → attainment',
                            Icons.school,
                            () => openPage(
                                context,
                                CourseListPage(
                                    repository: widget.repository,
                                    isAdmin: widget.isAdmin,
                                    ocrService: widget.ocrService))),
                        if (widget.isAdmin) ...[
                          ActionTile(
                              'Manage teachers',
                              'Approve access; assign teachers inside a course offering',
                              Icons.people,
                              () => openPage(context,
                                  TeachersPage(repository: widget.repository))),
                          ActionTile(
                              'Program reports',
                              'Aggregate course PO contributions for one year and term',
                              Icons.insights,
                              () => openPage(
                                  context,
                                  ProgramReportPage(
                                      repository: widget.repository))),
                        ],
                        const SizedBox(height: 24),
                        const Text('Existing scanner'),
                        ActionTile(
                            'Quick scan',
                            'Unassigned scans are saved separately from course attainment',
                            Icons.document_scanner,
                            () => openPage(
                                context,
                                ImageSourceScreen(
                                    ocrService: widget.ocrService),
                                name: ScanWorkflow.scannerRoute)),
                        ActionTile(
                            'Previous unassigned results',
                            'Results saved before course and exam setup',
                            Icons.history,
                            () => openPage(context, const ResultsScreen())),
                      ]);
                })
          ]);
}

class TeachersPage extends StatefulWidget {
  final WorkflowRepository repository;
  const TeachersPage({super.key, required this.repository});
  @override
  State<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends State<TeachersPage> {
  late Future<List<Json>> _teachers = widget.repository.teachers();
  bool _busy = false;
  void _reload() => setState(() {
        _teachers = widget.repository.teachers();
      });
  @override
  Widget build(BuildContext context) =>
      WorkflowPage(title: 'Manage teachers', children: [
        const Text(
            'Teachers create an account and verify their email first. Approval grants teacher access. Admin roles are assigned securely outside this screen.'),
        LoadView(
            future: _teachers,
            retry: _reload,
            builder: (teachers) => Column(children: [
                  if (teachers.isEmpty) const Text('No registered teachers.'),
                  for (final teacher in teachers)
                    SwitchListTile(
                        title: Text(teacher['full_name']),
                        subtitle: Text(teacher['email']),
                        value: teacher['approved'],
                        onChanged: _busy
                            ? null
                            : (approved) async {
                                setState(() => _busy = true);
                                try {
                                  await widget.repository
                                      .approveTeacher(teacher['id'], approved);
                                  _reload();
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              }),
                ]))
      ]);
}
