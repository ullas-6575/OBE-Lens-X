import 'bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/local_preview_services.dart';

const _localPreview = bool.fromEnvironment(
  'OBELENS_LOCAL_PREVIEW',
  defaultValue: false,
);

Future<void> main(List<String> arguments) async {
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
  // Linux's link plugin receives running-instance events, but does not retain
  // the initial process arguments. Wait until SessionGate is subscribed.
  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.linux &&
      arguments.isNotEmpty) {
    final uri = Uri.tryParse(arguments.first);
    if (uri?.scheme == 'com.obelens.app' && uri?.host == 'auth-callback') {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await Supabase.instance.client.auth.getSessionFromUrl(uri!);
        } catch (_) {
          // Do not log a callback URL: it may contain authentication tokens.
          debugPrint(
              'Password reset link could not be opened. Request a new link.');
        }
      });
    }
  }
}
