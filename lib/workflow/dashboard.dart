import 'package:flutter/material.dart';
import '../services/ocr_service.dart';
import 'models.dart';
import 'registration_page.dart';
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

  void _reloadProfile() => setState(() {
        _profile = widget.repository.profile();
      });

  Widget _welcome(Json profile) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text('Welcome, ${profile['full_name']}',
          style: Theme.of(context).textTheme.headlineSmall));

  /// New and rejected accounts see only this notice until an admin decides.
  Widget _registrationNotice(Json profile) {
    final theme = Theme.of(context);
    final rejected =
        RegistrationStatus.of(profile) == RegistrationStatus.rejected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(rejected ? Icons.block : Icons.hourglass_top,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              rejected
                  ? 'Your registration was rejected. Contact an administrator.'
                  : 'Your account is awaiting teacher approval.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
                onPressed: _reloadProfile,
                child: const Text('Check approval')),
          ],
        ),
      ),
    );
  }

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
          ActionTile(
              'Registrations',
              'Approve or reject new accounts before they can sign in',
              Icons.how_to_reg,
              () => openPage(
                  context, RegistrationsPage(repository: widget.repository))),
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
                retry: _reloadProfile,
                builder: (profile) {
                  if (!widget.isAdmin &&
                      RegistrationStatus.of(profile) !=
                          RegistrationStatus.approved) {
                    return _registrationNotice(profile);
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
