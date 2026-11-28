import 'dart:typed_data';
import 'dart:ui' as ui;

/// Synthetic ruled table for transport, cropping and browser smoke checks.
Future<Uint8List> marksheetPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
  final ink = ui.Paint()
    ..color = const ui.Color(0xff000000)
    ..strokeWidth = 2;
  for (final x in [50, 150, 250, 350, 450, 550]) {
    canvas.drawLine(ui.Offset(x.toDouble(), 50), ui.Offset(x.toDouble(), 790), ink);
  }
  for (final y in [50, 150, 230, 310, 390, 470, 550, 630, 710, 790]) {
    canvas.drawLine(ui.Offset(50, y.toDouble()), ui.Offset(550, y.toDouble()), ink);
  }
  canvas.drawLine(const ui.Offset(175, 175), const ui.Offset(210, 175), ink);
  canvas.drawLine(const ui.Offset(210, 175), const ui.Offset(185, 215), ink);
  final picture = recorder.endRecording();
  final image = await picture.toImage(650, 850);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return png!.buffer.asUint8List();
}
