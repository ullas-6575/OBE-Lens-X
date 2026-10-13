import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'ocr_http_client.dart' if (dart.library.io) 'ocr_http_client_io.dart';
import '../models/marks_table_data.dart';
import '../models/table_selection.dart';

/// Service interface for Optical Character Recognition on marks tables
abstract class BaseOcrService {
  Future<MarksTableData> processImage({
    String? imagePath,
    String tableType = '1-4',
    TableSelection? selection,
    void Function(String status, double progress)? onProgress,
  });
}

/// Detection has no recognition side effects; null means manual selection.
abstract class TableDetectionService {
  Future<TableSelection?> detectTable(
      {required String imagePath, int rotation = 0});
}

/// Explicit manual-entry fallback for tests or offline workflows.
/// Implement [BaseOcrService] and inject it through MarkSheetApp.ocrService
/// to provide extracted marks without changing the screens.
class PlaceholderOcrService implements BaseOcrService {
  const PlaceholderOcrService();

  @override
  Future<MarksTableData> processImage({
    String? imagePath,
    String tableType = '1-4',
    TableSelection? selection,
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Preparing marks table...', 0.15);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    onProgress?.call('Initializing grid...', 0.80);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final data = MarksTableData.empty(
      imagePath: imagePath,
      tableType: tableType,
    ).copyWith(confidenceScore: 0);
    onProgress?.call('Complete.', 1.0);
    return data;
  }
}

/// Simulated OCR Service for fast testing without invoking native binaries
class MockOcrService implements BaseOcrService {
  final Duration stepDuration;
  final MarksTableData? overrideData;

  const MockOcrService({
    this.stepDuration = const Duration(milliseconds: 100),
    this.overrideData,
  });

  @override
  Future<MarksTableData> processImage({
    String? imagePath,
    String tableType = '1-4',
    TableSelection? selection,
    void Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Processing image...', 0.5);
    if (stepDuration > Duration.zero) await Future.delayed(stepDuration);
    onProgress?.call('Extraction complete!', 1.0);

    return overrideData ??
        MarksTableData.empty(
          imagePath: imagePath,
          tableType: tableType,
        );
  }
}

class LocalOcrService implements BaseOcrService, TableDetectionService {
  static const MethodChannel _channel =
      MethodChannel('com.example.my_app/local_ocr');

  final String modelAssetPath;
  const LocalOcrService(
      {this.modelAssetPath = 'assets/ocr_model/inference.onnx'});

  @override
  Future<MarksTableData> processImage({
    String? imagePath,
    String tableType = '1-4',
    TableSelection? selection,
    void Function(String status, double progress)? onProgress,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw UnsupportedError('Local OCR is available only on Android devices.');
    }
    if (imagePath == null || imagePath.isEmpty) {
      throw const FormatException('Choose a photograph before OCR.');
    }
    if (selection == null || !selection.isValid) {
      throw const FormatException('Select the rubric corners before OCR.');
    }

    onProgress?.call('Loading local OCR model...', 0.15);
    onProgress?.call('Running on-device table recognition...', 0.6);

    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'processTable',
      {
        // Android loads the asset once; avoid copying the model through Dart
        // and the platform channel for every scan.
        'modelAssetPath': modelAssetPath,
        'imagePath': imagePath,
        'tableType': tableType,
        'rotation': selection.rotation,
        'corners': selection.corners.map((p) => [p.dx, p.dy]).toList(),
      },
    );

    if (result == null) {
      throw const FormatException('Local OCR returned no table data.');
    }

    final data = MarksTableData.fromJson(
      Map<String, dynamic>.from(
        result.map((key, value) => MapEntry(key.toString(), value)),
      ),
      imagePath: imagePath,
    );

    if (data.tableType != tableType) {
      throw const FormatException('Local OCR returned the wrong table type');
    }

    onProgress?.call('Ready for teacher review', 1.0);
    return data;
  }

  @override
  Future<TableSelection?> detectTable(
      {required String imagePath, int rotation = 0}) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'detectTable',
      {'imagePath': imagePath, 'rotation': rotation},
    );
    if (result == null) {
      throw const FormatException('Local detection returned no data.');
    }
    final body = Map<String, dynamic>.from(result);
    return body['detected'] == true ? TableSelection.fromDetection(body) : null;
  }
}

/// Python API client. Web defaults to the same-origin Docker reverse proxy.
class PythonOcrService implements BaseOcrService, TableDetectionService {
  final String? endpoint;
  final Duration timeout;
  const PythonOcrService(
      {this.endpoint, this.timeout = const Duration(minutes: 3)});

  @override
  Future<MarksTableData> processImage(
      {String? imagePath,
      String tableType = '1-4',
      TableSelection? selection,
      void Function(String status, double progress)? onProgress}) async {
    onProgress?.call('Uploading marks table...', .15);
    final body = await _postImage(
        '/ocr/table',
        imagePath,
        {
          'table_type': tableType,
          if (selection != null) ...selection.toJson(),
        },
        onUploaded: () => onProgress?.call(
            'Correcting perspective and recognizing cells...', .45));
    final data = MarksTableData.fromJson(body, imagePath: imagePath);
    if (data.tableType != tableType) {
      throw const FormatException('OCR returned the wrong table type');
    }
    onProgress?.call('Ready for teacher review', 1);
    return data;
  }

  @override
  Future<TableSelection?> detectTable(
      {required String imagePath, int rotation = 0}) async {
    final body = await _postImage(
        '/ocr/detect', imagePath, {'rotation': rotation},
        requestTimeout: const Duration(seconds: 20));
    return body['detected'] == true ? TableSelection.fromDetection(body) : null;
  }

  Future<Map<String, dynamic>> _postImage(
      String path, String? imagePath, Map<String, dynamic> fields,
      {VoidCallback? onUploaded, Duration? requestTimeout}) async {
    const configuredUrl = String.fromEnvironment('OCR_API_URL');
    final base = endpoint ??
        (configuredUrl.isNotEmpty
            ? configuredUrl
            : kIsWeb
                ? Uri.base.origin
                : Platform.isAndroid
                    ? 'http://10.0.2.2:8765'
                    : 'http://127.0.0.1:8765');
    if (imagePath != null &&
        await XFile(imagePath).length() > 10 * 1024 * 1024) {
      throw const FormatException('Select an image smaller than 10 MB.');
    }
    final bytes = imagePath == null
        ? (await rootBundle.load('assets/sample_marksheet.png'))
            .buffer
            .asUint8List()
        : await XFile(imagePath).readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Select an image smaller than 10 MB.');
    }
    final client = createOcrClient();
    try {
      return await (() async {
        const token = String.fromEnvironment('OCR_API_TOKEN');
        final payload = utf8.encode(
            jsonEncode({'image_base64': base64Encode(bytes), ...fields}));
        final pending = client.post(
          Uri.parse('${base.replaceFirst(RegExp(r'/+$'), '')}$path'),
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: payload,
        );
        onUploaded?.call();
        final response = await pending;
        final body =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (response.statusCode != 200) {
          throw FormatException(
              body['error'] as String? ?? 'OCR request failed');
        }
        return body;
      })()
          .timeout(requestTimeout ?? timeout);
    } finally {
      client.close();
    }
  }
}
