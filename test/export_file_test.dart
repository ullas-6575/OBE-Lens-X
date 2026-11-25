import 'dart:io';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/workflow/export_file.dart';

class SaveSelector extends FileSelectorPlatform {
  String? path;
  String? name;
  @override
  Future<FileSaveLocation?> getSaveLocation(
      {List<XTypeGroup>? acceptedTypeGroups,
      SaveDialogOptions options = const SaveDialogOptions()}) async {
    name = options.suggestedName;
    return path == null ? null : FileSaveLocation(path!);
  }
}

void main() {
  testWidgets('Linux saves bytes and cancel writes nothing', (tester) async {
    await tester.runAsync(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final previous = FileSelectorPlatform.instance;
      final selector = SaveSelector();
      FileSelectorPlatform.instance = selector;
      final directory = await Directory.systemTemp.createTemp('export-test-');
      addTearDown(() async {
        debugDefaultTargetPlatformOverride = null;
        FileSelectorPlatform.instance = previous;
        await directory.delete(recursive: true);
      });
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      })));
      for (final extension in ['pdf', 'csv', 'xls']) {
        selector.path = '${directory.path}/report.$extension';
        await exportFile(context, Uint8List.fromList([1, 2, 3]),
            name: 'report.$extension',
            mimeType: 'application/octet-stream',
            title: 'Report');
        expect(await File(selector.path!).readAsBytes(), [1, 2, 3]);
        expect(selector.name, 'report.$extension');
      }
      selector.path = null;
      await exportFile(context, Uint8List(0),
          name: 'cancel.csv', mimeType: 'text/csv', title: 'Report');
      expect(directory.listSync().length, 3);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('Android export sends files to the sharing plugin',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final temp = Directory.systemTemp.createTempSync('share-test-');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => temp.path);
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, null);
      await temp.delete(recursive: true);
    });
    MethodCall? shared;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'shareFiles') shared = call;
      return 'success';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const SizedBox();
    })));
    await tester.runAsync(() async {
      for (final entry in {
        'pdf': 'application/pdf',
        'csv': 'text/csv',
        'xls': 'application/vnd.ms-excel',
      }.entries) {
        shared = null;
        await exportFile(context, Uint8List.fromList([1, 2, 3]),
            name: 'report.${entry.key}', mimeType: entry.value, title: 'Report');
        expect(shared, isNotNull);
        expect(shared!.arguments['mimeTypes'], [entry.value]);
        final path = (shared!.arguments['paths'] as List).single as String;
        expect(path.endsWith('report.${entry.key}'), isTrue);
        expect(await File(path).readAsBytes(), [1, 2, 3]);
      }
    });
    debugDefaultTargetPlatformOverride = null;
  });
}
