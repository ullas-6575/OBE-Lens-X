import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'services/ocr_service.dart';
import 'theme/app_theme.dart';

class MarkSheetApp extends StatelessWidget {
  final BaseOcrService? ocrService;

  const MarkSheetApp({super.key, this.ocrService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarkSheet OCR',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AuthScreen(ocrService: ocrService),
    );
  }
}
