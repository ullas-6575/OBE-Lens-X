import 'dart:ui';

/// Corners are TL, TR, BR, BL in the EXIF-oriented image AFTER [rotation].
/// Coordinates are normalized to the image, never to the screen/letterboxing.
class TableSelection {
  final List<Offset> corners;
  final int rotation;

  TableSelection({required List<Offset> corners, this.rotation = 0})
      : corners = List.unmodifiable(corners);

  factory TableSelection.initial() => TableSelection(corners: const [
        Offset(.08, .08),
        Offset(.92, .08),
        Offset(.92, .92),
        Offset(.08, .92),
      ]);

  bool get isValid {
    if (![0, 90, 180, 270].contains(rotation) || corners.length != 4) {
      return false;
    }
    for (final p in corners) {
      if (!p.dx.isFinite ||
          !p.dy.isFinite ||
          p.dx < 0 ||
          p.dx > 1 ||
          p.dy < 0 ||
          p.dy > 1) return false;
    }
    double area = 0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % 4];
      final c = corners[(i + 2) % 4];
      final ab = b - a;
      final bc = c - b;
      if (ab.dx * bc.dy - ab.dy * bc.dx <= 0) return false;
      area += a.dx * b.dy - b.dx * a.dy;
    }
    return area / 2 > .001 &&
        corners[0].dx < corners[1].dx &&
        corners[3].dx < corners[2].dx &&
        corners[0].dy < corners[3].dy &&
        corners[1].dy < corners[2].dy;
  }

  TableSelection moveCorner(int index, Offset point) {
    final updated = List<Offset>.of(corners);
    updated[index] = Offset(point.dx.clamp(0, 1), point.dy.clamp(0, 1));
    return TableSelection(corners: updated, rotation: rotation);
  }

  TableSelection rotateClockwise() {
    final rotated = corners.map((p) => Offset(1 - p.dy, p.dx)).toList();
    return TableSelection(
      corners: [rotated[3], rotated[0], rotated[1], rotated[2]],
      rotation: (rotation + 90) % 360,
    );
  }

  TableSelection rotateCounterclockwise() =>
      rotateClockwise().rotateClockwise().rotateClockwise();

  Map<String, dynamic> toJson() {
    if (!isValid) {
      throw const FormatException('Select four valid table corners.');
    }
    return {
      'rotation': rotation,
      'normalized_corners': corners.map((p) => [p.dx, p.dy]).toList(),
    };
  }

  factory TableSelection.fromDetection(Map<String, dynamic> json) {
    final points = json['normalized_corners'] as List<dynamic>;
    final selection = TableSelection(
      rotation: json['rotation'] as int? ?? 0,
      corners: points.map((point) {
        final pair = point as List<dynamic>;
        if (pair.length != 2) {
          throw const FormatException('Invalid table corner');
        }
        return Offset((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
      }).toList(),
    );
    if (!selection.isValid) {
      throw const FormatException('Invalid table corners');
    }
    return selection;
  }
}
