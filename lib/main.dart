import 'bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/local_preview_services.dart';

const _localPreview = bool.fromEnvironment(
  'OBELENS_LOCAL_PREVIEW',
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_localPreview) {
    bootstrap(
      authService: LocalPreviewAuthService(),
      workflowRepository: LocalPreviewWorkflowRepository(),
      enableTeacherPreview: true,
    );
    return;
  }
  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://tnvjmfqjtgttnrifqahs.supabase.co',
    ),
    publishableKey: const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: 'sb_publishable_Kx-8_d9TGrcEVoOqZWHmWw_b2QwIE0f',
    ),
  );
  bootstrap();
}
