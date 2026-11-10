import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import 'models.dart';
import 'repository.dart';
import 'ui.dart';
import 'course_pages.dart';

class Dashboard extends StatefulWidget {
  final WorkflowRepository repository;
  final bool isAdmin;
  final bool enableTeacherPreview;
  final BaseOcrService? ocrService;
  final Future<void> Function() signOut;
  const Dashboard(
      {super.key,
      required this.repository,
      required this.isAdmin,
      required this.signOut,
      this.enableTeacherPreview = false,
      this.ocrService});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late Future<Json> _profile = widget.repository.profile();
  bool _previewingTeacher = false;

  Widget _welcome(Json profile) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text('Welcome, ${profile['full_name']}',
          style: Theme.of(context).textTheme.headlineSmall));

  Widget _adminDashboard(Json profile) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _welcome(profile),
          ActionTile(
              'Manage courses',
              'Create courses, set CO–PO links, and configure offerings',
              Icons.school,
              () => openPage(
                  context,
                  CourseListPage(
                      repository: widget.repository,
                      isAdmin: true,
                      ocrService: widget.ocrService))),
          if (widget.enableTeacherPreview)
            ActionTile(
                'Preview teacher dashboard',
                'Try the assigned-course workflow with local demo data',
                Icons.school_outlined,
                () => setState(() => _previewingTeacher = true)),
        ],
      );

  Widget _teacherDashboard(Json profile, {bool demoPreview = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _welcome(demoPreview ? {'full_name': 'Preview Teacher'} : profile),
          ActionTile(
              'Assigned courses',
              'Map questions, scan marks with OCR, and view course results',
              Icons.school,
              () => openPage(
                  context,
                  CourseListPage(
                      repository: widget.repository,
                      isAdmin: false,
                      ocrService: widget.ocrService))),
        ],
      );

  @override
  Widget build(BuildContext context) => WorkflowPage(
          title: widget.isAdmin
              ? _previewingTeacher
                  ? 'Teacher dashboard preview'
                  : 'Admin dashboard'
              : 'Teacher dashboard',
          actions: [
            if (_previewingTeacher)
              IconButton(
                  tooltip: 'Return to admin dashboard',
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  onPressed: () => setState(() => _previewingTeacher = false))
            else
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
                  if (_previewingTeacher) {
                    return _teacherDashboard(profile, demoPreview: true);
                  }
                  return widget.isAdmin
                      ? _adminDashboard(profile)
                      : _teacherDashboard(profile);
                })
          ]);
}
