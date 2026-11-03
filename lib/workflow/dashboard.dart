import 'package:flutter/material.dart';
import '../screens/image_source_screen.dart';
import '../models/scan_workflow.dart';
import '../services/ocr_service.dart';
import 'models.dart';
import 'repository.dart';
import 'ui.dart';
import 'course_pages.dart';

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
                      ]);
                })
          ]);
}
