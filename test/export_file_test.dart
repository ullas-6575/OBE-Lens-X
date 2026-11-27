import 'dart:io';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/workflow/export_file.dart';
import 'package:my_app/workflow/report_export.dart';

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
  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    testWidgets('$platform saves Excel and cancel writes nothing',
        (tester) async {
      await tester.runAsync(() async {
        debugDefaultTargetPlatformOverride = platform;
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
        selector.path = '${directory.path}/report.xls';
        await const ShareReportExporter().export(context, 'CSE3200 - Final', [
          ['Course', 'CSE3200'],
          ['Roll no', 'CO1', 'CO2', 'CO3', 'CO4'],
          ['001', '1', '0', '1', '0'],
          ['CO', 'Eligible', 'Attained', 'Attainment %', 'Level'],
          ['CO1', '1', '1', '100', 'L4'],
          ['PO', 'Contribution %', 'Level'],
          ['PO1', '100', 'L4'],
        ]);
        final workbook = await File(selector.path!).readAsString();
        expect(RegExp('<Worksheet ').allMatches(workbook).length, 4);
        expect(workbook, contains('<Data ss:Type="String">001</Data>'));
        expect(selector.name, 'CSE3200 - Final-attainment.xls');
        selector.path = null;
        await exportFile(context, Uint8List(0),
            name: 'cancel.xls',
            mimeType: 'application/vnd.ms-excel',
            title: 'Report');
        expect(directory.listSync().length, 1);
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }

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
      await const ShareReportExporter().export(context, 'CSE3200 - Final', [
        ['Course', 'CSE3200'],
        ['Roll no', 'CO1', 'CO2', 'CO3', 'CO4'],
        ['001', '1', '0', '1', '0'],
        ['CO', 'Eligible', 'Attained', 'Attainment %', 'Level'],
        ['CO1', '1', '1', '100', 'L4'],
        ['PO', 'Contribution %', 'Level'],
        ['PO1', '100', 'L4'],
      ]);
    });
    expect(shared, isNotNull);
    expect(shared!.arguments['mimeTypes'], ['application/vnd.ms-excel']);
    final path = (shared!.arguments['paths'] as List).single as String;
    expect(path, endsWith('/CSE3200 - Final-attainment.xls'));
    final workbook = File(path).readAsStringSync();
    expect(workbook, contains('<Worksheet ss:Name="Student CO attainment">'));
    expect(workbook, contains('<Data ss:Type="String">001</Data>'));
    expect(RegExp('<Worksheet ').allMatches(workbook).length, 4);
    debugDefaultTargetPlatformOverride = null;
  });
}
