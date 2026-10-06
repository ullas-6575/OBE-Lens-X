import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/marks_table_data.dart';
import 'package:my_app/models/table_selection.dart';
import 'package:my_app/screens/image_processing_screen.dart';
import 'package:my_app/screens/image_source_screen.dart';
import 'package:my_app/screens/table_crop_screen.dart';
import 'package:my_app/widgets/table_crop_overlay.dart';
import 'package:my_app/services/ocr_service.dart';

const sample = 'assets/sample_marksheet.png';

class RecordingService implements BaseOcrService, TableDetectionService {
  final Future<TableSelection?> detection;
  final bool failOcr;
  int uploads = 0;
  String? tableType;
  TableSelection? selection;
  final result = Completer<MarksTableData>();
  final detectionStarted = Completer<void>();
  RecordingService({Future<TableSelection?>? detection, this.failOcr = false})
      : detection = detection ?? Future.value(null);

  @override
  Future<TableSelection?> detectTable(
      {required String imagePath, int rotation = 0}) {
    if (!detectionStarted.isCompleted) detectionStarted.complete();
    return detection;
  }

  @override
  Future<MarksTableData> processImage(
      {String? imagePath,
      String tableType = '1-4',
      TableSelection? selection,
      void Function(String, double)? onProgress}) {
    uploads++;
    this.tableType = tableType;
    this.selection = selection;
    if (failOcr) {
      return Future.error(const FormatException('Please adjust the table.'));
    }
    return result.future;
  }
}

Future<void> openCrop(WidgetTester tester, RecordingService service,
    {String imagePath = sample}) async {
  await tester.pumpWidget(MaterialApp(
      home: TableCropScreen(
          imagePath: imagePath, tableType: '5-8', ocrService: service)));
  await waitForDetection(tester, service);
  expect(find.byType(TableCropOverlay), findsOneWidget);
  await tester.ensureVisible(find.byKey(const ValueKey('crop-continue')));
}

Future<void> waitForDetection(
    WidgetTester tester, RecordingService service) async {
  // File I/O and image decoding run in real time; widget callbacks need frames
  // in the test's fake clock. Wait for the observable event while pumping both.
  for (var attempt = 0;
      attempt < 250 && !service.detectionStarted.isCompleted;
      attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(service.detectionStarted.isCompleted, isTrue);
  await tester.pump();
}

TableSelection currentSelection(WidgetTester tester) =>
    tester.widget<TableCropOverlay>(find.byType(TableCropOverlay)).selection;

void main() {
  testWidgets(
      'Camera EXIF orientation is applied before preview and user rotation',
      (tester) async {
    await openCrop(tester, RecordingService(),
        imagePath: 'test/fixtures/exif_orientation_6.jpg');
    final overlay =
        tester.widget<TableCropOverlay>(find.byType(TableCropOverlay));
    // Stored pixels are 40x80 with EXIF orientation 6 (90 degrees clockwise).
    expect(overlay.imageSize, const Size(80, 40));
    expect(overlay.selection.rotation, 0);
    await tester.tap(find.text('Rotate Right'));
    await tester.pump();
    expect(currentSelection(tester).rotation, 90);
  });

  test('Rotation keeps corner identities and normalized geometry', () {
    final selection = TableSelection(corners: const [
      Offset(.1, .2),
      Offset(.8, .1),
      Offset(.9, .7),
      Offset(.2, .9),
    ]);
    final right = selection.rotateClockwise();
    expect(right.rotation, 90);
    expect(right.corners[0].dx, closeTo(.1, 1e-9));
    expect(right.corners[0].dy, closeTo(.2, 1e-9));
    expect(right.corners[1], const Offset(.8, .1));
    final restored = right.rotateCounterclockwise();
    for (var i = 0; i < 4; i++) {
      expect((restored.corners[i] - selection.corners[i]).distance,
          lessThan(1e-9));
    }
    expect(restored.rotation, 0);
    expect(selection.moveCorner(0, const Offset(.95, .95)).isValid, isFalse);
    expect(
        selection.moveCorner(0, const Offset(-1, -1)).corners[0], Offset.zero);
  });

  testWidgets(
      'Detected corners need only Continue; preserves group and rotation',
      (tester) async {
    final detected = TableSelection(corners: const [
      Offset(.1, .15),
      Offset(.8, .12),
      Offset(.85, .85),
      Offset(.12, .9),
    ]);
    final service = RecordingService(detection: Future.value(detected));
    await openCrop(tester, service);
    expect(currentSelection(tester), same(detected));
    expect(service.uploads, 0);
    await tester.tap(find.text('Rotate Right'));
    await tester.pump();
    expect(currentSelection(tester).rotation, 90);
    await tester.tap(find.text('Rotate Left'));
    await tester.pump();
    expect(currentSelection(tester).rotation, 0);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(currentSelection(tester), same(detected));
    await tester.tap(find.text('Rotate Left'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('crop-continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(service.uploads, 1);
    expect(service.tableType, '5-8');
    expect(service.selection!.rotation, 270);
    expect(service.selection!.isValid, isTrue);
    expect(find.byType(ImageProcessingScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.result.complete(MarksTableData.empty(tableType: '5-8'));
    await tester.pump();
  });

  testWidgets(
      'Dragging uses image coordinates and late detection does not overwrite edits',
      (tester) async {
    final pending = Completer<TableSelection?>();
    final service = RecordingService(detection: pending.future);
    await openCrop(tester, service);
    final imageSize = tester.getSize(find.byType(Image));
    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('crop-corner-0'))));
    await gesture.moveBy(const Offset(35, 35));
    await tester.pump();
    final before = currentSelection(tester).corners[0];
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();
    await gesture.up();
    final moved = currentSelection(tester);
    expect(
        moved.corners[0].dx - before.dx, closeTo(20 / imageSize.width, .001));
    expect(
        moved.corners[0].dy - before.dy, closeTo(10 / imageSize.height, .001));
    pending.complete(TableSelection.initial());
    await tester.pumpAndSettle();
    expect(currentSelection(tester), same(moved));
    expect(service.uploads, 0);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(currentSelection(tester).corners, TableSelection.initial().corners);
  });

  testWidgets(
      'Failed detection allows manual scan and failed OCR returns to same crop',
      (tester) async {
    final service = RecordingService(failOcr: true);
    await openCrop(tester, service);
    expect(find.textContaining('couldn’t locate the table automatically'),
        findsOneWidget);
    await tester.tap(find.text('Rotate Right'));
    await tester.pump();
    final selection = currentSelection(tester);
    await tester.tap(find.byKey(const ValueKey('crop-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Adjust Table Corners'), findsOneWidget);
    await tester.tap(find.text('Adjust Table Corners'));
    await tester.pumpAndSettle();
    expect(currentSelection(tester), same(selection));
    expect(service.uploads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Unavailable detection and short landscape layout remain usable',
      (tester) async {
    tester.view.physicalSize = const Size(720, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<TableSelection?>();
    await openCrop(tester, RecordingService(detection: pending.future));
    pending.completeError(const SocketException('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Automatic detection is unavailable'),
        findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('crop-continue')));
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('crop-continue')))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Camera and gallery both open crop before starting OCR',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    final requests = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      requests.add(call);
      return File(sample).absolute.path;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    for (final button in ['Capture Mark Sheet', 'Upload Table Image']) {
      final service = RecordingService();
      await tester.pumpWidget(
          MaterialApp(home: ImageSourceScreen(ocrService: service)));
      await tester.ensureVisible(find.text(button));
      await tester.tap(find.text(button));
      await tester.pump();
      await waitForDetection(tester, service);
      await tester.pumpAndSettle();
      expect(find.byType(TableCropScreen), findsOneWidget);
      expect(service.uploads, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ImageSourceScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    expect(requests.length, 2);
  });
}
