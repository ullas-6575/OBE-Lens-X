// Browser-only diagnostic entrypoint, excluded from the production web target.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/services/ocr_service.dart';
import 'package:my_app/widgets/selected_image.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Checking browser OCR…')))));
  try {
    final sample = await rootBundle.load('assets/sample_marksheet.png');
    final file =
        XFile.fromData(sample.buffer.asUint8List(), mimeType: 'image/png');
    if (!file.path.startsWith('blob:') || !selectedImageExists(file.path)) {
      throw StateError('Expected a browser blob URL');
    }
    final loaded = Completer<void>();
    final stream =
        selectedImageProvider(file.path).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      info.dispose();
      if (!loaded.isCompleted) loaded.complete();
    }, onError: (Object error, StackTrace? stack) {
      if (!loaded.isCompleted) loaded.completeError(error, stack);
    });
    stream.addListener(listener);
    try {
      await loaded.future.timeout(const Duration(seconds: 30));
    } finally {
      stream.removeListener(listener);
    }
    const service = PythonOcrService();
    final selection = await service.detectTable(imagePath: file.path);
    if (selection == null || !selection.isValid) {
      throw StateError('Browser detection failed');
    }
    final result = await service.processImage(
        imagePath: file.path, tableType: '5-8', selection: selection);
    final count =
        result.cellResults.values.fold<int>(0, (n, parts) => n + parts.length);
    if (count != 28 || result.tableType != '5-8' || result.isVerified) {
      throw StateError('Unexpected browser OCR result');
    }
    html.document.documentElement!.setAttribute('data-obelens-check', 'PASS');
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(child: Text('PASS: browser preview and OCR')))));
  } catch (error) {
    html.document.documentElement!
        .setAttribute('data-obelens-check', 'FAIL: $error');
    runApp(
        MaterialApp(home: Scaffold(body: Center(child: Text('FAIL: $error')))));
  }
}
