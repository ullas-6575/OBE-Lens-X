import 'package:flutter/material.dart';

import 'screens/session_gate.dart';
import 'workflow/repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';
import 'services/ocr_service.dart';
import 'theme/app_theme.dart';

class MarkSheetApp extends StatelessWidget {
  final BaseOcrService? ocrService;
  final AuthService? authService;
  final WorkflowRepository? workflowRepository;

  const MarkSheetApp(
      {super.key, this.ocrService, this.authService, this.workflowRepository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'obelens',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: SessionGate(
          ocrService: ocrService,
          auth: authService ?? const SupabaseAuthService(),
          repository: workflowRepository ??
              SupabaseWorkflowRepository(Supabase.instance.client)),
    );
  }
}
