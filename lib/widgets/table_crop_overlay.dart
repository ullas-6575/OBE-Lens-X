import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/table_selection.dart';

/// The image and handles share one fitted rectangle, excluding letterboxing.
class TableCropOverlay extends StatelessWidget {
  final ImageProvider image;
  final Size imageSize;
  final TableSelection selection;
  final void Function(int index, Offset normalizedDelta) onCornerMoved;

  const TableCropOverlay({
    super.key,
    required this.image,
    required this.imageSize,
    required this.selection,
    required this.onCornerMoved,
  });

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, layout) {
        final rotated = selection.rotation % 180 != 0;
        final size =
            rotated ? Size(imageSize.height, imageSize.width) : imageSize;
        final scale = math.min(math.max(1, layout.maxWidth - 48) / size.width,
            math.max(1, layout.maxHeight - 48) / size.height);
        final rect = Rect.fromCenter(
            center: Offset(layout.maxWidth / 2, layout.maxHeight / 2),
            width: size.width * scale,
            height: size.height * scale);
        final points = selection.corners
            .map((p) =>
                rect.topLeft + Offset(p.dx * rect.width, p.dy * rect.height))
            .toList();
        const labels = ['Top left', 'Top right', 'Bottom right', 'Bottom left'];
        final color = Theme.of(context).colorScheme.primary;
        return Stack(children: [
          Positioned.fromRect(
              rect: rect,
              child: RotatedBox(
                  quarterTurns: selection.rotation ~/ 90,
                  child: Image(
                      image: image,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium))),
          Positioned.fill(
              child: IgnorePointer(
                  child:
                      CustomPaint(painter: _SelectionPainter(points, color)))),
          for (var i = 0; i < 4; i++)
            Positioned(
                left: points[i].dx - 24,
                top: points[i].dy - 24,
                width: 48,
                height: 48,
                child: Semantics(
                    label: '${labels[i]} table corner. Drag to adjust.',
                    child: Tooltip(
                        message: '${labels[i]} corner',
                        child: Focus(
                            onKeyEvent: (_, event) {
                              if (event is! KeyDownEvent &&
                                  event is! KeyRepeatEvent) {
                                return KeyEventResult.ignored;
                              }
                              final delta = {
                                LogicalKeyboardKey.arrowLeft:
                                    const Offset(-1, 0),
                                LogicalKeyboardKey.arrowRight:
                                    const Offset(1, 0),
                                LogicalKeyboardKey.arrowUp: const Offset(0, -1),
                                LogicalKeyboardKey.arrowDown:
                                    const Offset(0, 1),
                              }[event.logicalKey];
                              if (delta == null) return KeyEventResult.ignored;
                              onCornerMoved(
                                  i,
                                  Offset(delta.dx / rect.width,
                                      delta.dy / rect.height));
                              return KeyEventResult.handled;
                            },
                            child: Builder(
                                builder: (context) => GestureDetector(
                                    key: ValueKey('crop-corner-$i'),
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () =>
                                        Focus.of(context).requestFocus(),
                                    onPanUpdate: (details) => onCornerMoved(
                                        i,
                                        Offset(details.delta.dx / rect.width,
                                            details.delta.dy / rect.height)),
                                    child: Center(
                                        child: Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: color,
                                                border: Border.all(
                                                    color: Colors.white,
                                                    width: 3),
                                                boxShadow: const [
                                                  BoxShadow(
                                                      color: Colors.black45,
                                                      blurRadius: 5)
                                                ]))))))))),
        ]);
      });
}

class _SelectionPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  _SelectionPainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final polygon = Path()..addPolygon(points, true);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(polygon, Offset.zero);
    canvas.drawPath(outside, Paint()..color = Colors.black.withOpacity(.58));
    canvas.drawPath(
        polygon,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
