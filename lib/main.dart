import 'bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/local_preview_services.dart';

const _localPreview = bool.fromEnvironment(
  'OBELENS_LOCAL_PREVIEW',
  defaultValue: true,
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
    url: const String.fromEnvironment('SUPABASE_URL',
        defaultValue: 'https://mleeksafajtfzwmkbyib.supabase.co'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY',
        defaultValue: 'sb_publishable_CGqB99MEfrYnD8aumMLwNA__20Dq5Lq'),
  );
  // await Supabase.initialize(
  //   url: 'https://tjlxhmzhoizuwxfqphpd.supabase.co',
  //   publishableKey: 'sb_publishable_449LYMHbfizw6tpXLlmSUA_NAgRCiWk',
  // );
  bootstrap();
}
