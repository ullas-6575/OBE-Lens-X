import 'bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://mleeksafajtfzwmkbyib.supabase.co',
    publishableKey: 'sb_publishable_CGqB99MEfrYnD8aumMLwNA__20Dq5Lq',
  );
  // await Supabase.initialize(
  //   url: const String.fromEnvironment('SUPABASE_URL',
  //       defaultValue: 'https://mleeksafajtfzwmkbyib.supabase.co'),
  //   publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY',
  //       defaultValue: 'sb_publishable_CGqB99MEfrYnD8aumMLwNA__20Dq5Lq'),
  // );

  bootstrap();
}
