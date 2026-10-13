import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'services/auth_service.dart';
import 'services/ocr_service.dart';
import 'theme/app_theme.dart';

class MarkSheetApp extends StatelessWidget {
  final BaseOcrService? ocrService;
  final AuthService? authService;

  const MarkSheetApp({super.key, this.ocrService, this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'obelens',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AuthScreen(ocrService: ocrService, authService: authService),
    );
  }
}
