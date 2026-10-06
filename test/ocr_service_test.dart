import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/models/table_selection.dart';
import 'package:my_app/services/ocr_service.dart';

Map<String, dynamic> payload() => {
      'tableType': '1-4',
      'scannedAt': '2026-10-03T10:00:00Z',
      'confidenceScore': .6,
      'cellMarks': {
        for (final q in MarksTableData.type1Questions)
          q: {
            for (final p in MarksTableData.parts)
              p: q == '1' && p == 'a' ? '15' : ''
          }
      },
      'cellResults': {
        for (final q in MarksTableData.type1Questions)
          q: {
            for (final p in MarksTableData.parts)
              p: {
                'text': '15',
                'confidence': .6,
                'needs_review': true,
                'reason': null
              }
          }
      },
    };

void main() {
  test('Android channel results decode all nested maps', () {
    // StandardMessageCodec returns Map<Object?, Object?> at every level.
    const codec = StandardMessageCodec();
    final native = codec.decodeMessage(codec.encodeMessage(payload())) as Map;
    final data = MarksTableData.fromJson(Map<String, dynamic>.from(native));
    expect(data.getMark('1', 'a'), '15');
    expect(data.cellResults['1']!['a']!.confidence, .6);
    expect(data.cellResults.length, 4);
  });

  test('Detection and manual OCR upload original bytes and normalized geometry',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final selection = TableSelection.initial().rotateClockwise();
    final paths = <String>[];
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      expect(base64Decode(body['image_base64'] as String),
          await File('assets/sample_marksheet.png').readAsBytes());
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/ocr/detect') {
        expect(body['rotation'], 90);
        request.response
            .write(jsonEncode({'detected': true, ...selection.toJson()}));
      } else {
        expect(body['rotation'], 90);
        expect(body['normalized_corners'],
            selection.toJson()['normalized_corners']);
        expect(body.containsKey('corners'), isFalse);
        request.response.write(jsonEncode(payload()));
      }
      await request.response.close();
    });
    try {
      final service =
          PythonOcrService(endpoint: 'http://127.0.0.1:${server.port}/');
      final detected = await service.detectTable(
          imagePath: 'assets/sample_marksheet.png', rotation: 90);
      expect(detected!.toJson(), selection.toJson());
      expect(paths, ['/ocr/detect']);
      await service.processImage(
          imagePath: 'assets/sample_marksheet.png', selection: detected);
      expect(paths, ['/ocr/detect', '/ocr/table']);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('Image bytes are uploaded with a length and review data is parsed',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestDone = server.first.then((request) async {
      expect(request.uri.path, '/ocr/table');
      expect(request.contentLength, greaterThan(0));
      final body = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      expect(body['table_type'], '1-4');
      expect(base64Decode(body['image_base64'] as String),
          await File('assets/sample_marksheet.png').readAsBytes());
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload()));
      await request.response.close();
    });
    try {
      final result =
          await PythonOcrService(endpoint: 'http://127.0.0.1:${server.port}')
              .processImage(imagePath: 'assets/sample_marksheet.png');
      await requestDone;
      expect(result.getMark('1', 'a'), '15');
      expect(result.cellResults['1']!['a']!.needsReview, isTrue);
      expect(result.isVerified, isFalse);
      expect(result.imagePath, 'assets/sample_marksheet.png');
    } finally {
      await server.close(force: true);
    }
  });

  test('Incomplete grids are rejected', () {
    final invalid = payload();
    (invalid['cellResults'] as Map).remove('4');
    expect(() => MarksTableData.fromJson(invalid), throwsFormatException);
  });

  test(
      'API parsing keeps numeric marks and distinguishes blanks from confusion',
      () {
    final response = payload();
    (response['cellMarks'] as Map)['1'] = {
      'a': 'o7',
      'b': '?',
      'c': '07',
      'd': '',
      'e': '/',
      'f': '-',
      'g': '0'
    };
    final details = (response['cellResults'] as Map)['1'] as Map;
    details['a'] = {'text': 'o7', 'confidence': .99, 'needs_review': false};
    details['b'] = {
      'text': '',
      'confidence': 0,
      'needs_review': true,
      'empty': true
    };
    details['d'] = {
      'text': '',
      'confidence': 0,
      'needs_review': true,
      'empty': false
    };
    final data = MarksTableData.fromJson(response);
    expect(data.cellMarks['1']!['a'], 'N/A');
    expect(data.cellResults['1']!['a']!.text, 'o7');
    expect(data.cellResults['1']!['a']!.needsAttention, isTrue);
    expect(data.cellResults['1']!['b']!.needsAttention, isFalse);
    expect(data.cellResults['1']!['d']!.needsAttention, isFalse);
    expect(data.getMark('1', 'c'), '07');
    expect(data.getMark('1', 'g'), '0');
    expect(data.calculateColumnTotal('1'), 7);
  });

  test('Extraction errors from Python reach the caller', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 422;
      request.response
          .write(jsonEncode({'error': 'Capture one complete rubric table.'}));
      await request.response.close();
    });
    try {
      await expectLater(
          PythonOcrService(endpoint: 'http://127.0.0.1:${server.port}')
              .processImage(imagePath: 'assets/sample_marksheet.png'),
          throwsFormatException);
    } finally {
      await server.close(force: true);
    }
  });

  test('Real Python server and pretrained model return all 28 cells', () async {
    final root = Directory.current.path;
    final process = await Process.start(
        '$root/.venv/bin/python', ['-m', 'ocr.server', '--port', '0'],
        workingDirectory: '$root/obelens-ocr',
        environment: {'PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK': 'True'});
    final errors = <String>[];
    process.stderr.transform(utf8.decoder).listen(errors.add);
    try {
      final line = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.startsWith('OCR API listening'))
          .timeout(const Duration(seconds: 20));
      final endpoint = line.split(' ').last;
      final service = PythonOcrService(endpoint: endpoint);
      final selection =
          await service.detectTable(imagePath: 'assets/sample_marksheet.png');
      expect(selection, isNotNull);
      expect(selection!.isValid, isTrue);
      final data = await service.processImage(
          imagePath: 'assets/sample_marksheet.png', selection: selection);
      expect(
          data.cellResults.values
              .fold<int>(0, (count, parts) => count + parts.length),
          28);
      expect(data.cellResults['1']!['a']!.cropBase64, isNotEmpty);
      expect(data.isVerified, isFalse);
      expect(
          data.cellMarks.values.expand((column) => column.values),
          everyElement(predicate<String>(
              (mark) => mark == 'N/A' || MarksTableData.isNumericMark(mark))));
      final blanks = data.cellResults.values
          .expand((column) => column.values)
          .where((cell) => cell.isEmpty);
      expect(blanks, isNotEmpty);
      expect(blanks.every((cell) => !cell.needsAttention), isTrue);
    } catch (error) {
      fail('$error\n${errors.join()}');
    } finally {
      process.kill(ProcessSignal.sigint);
      await process.exitCode;
    }
  },
      skip: !const bool.fromEnvironment('OCR_INTEGRATION'),
      timeout: const Timeout(Duration(minutes: 3)));
}
