"""Manual geometry in the EXIF-oriented, then clockwise-rotated image frame."""
from numbers import Integral
import cv2
import numpy as np
from .preprocessing import prepare_cell


def orient_image(image, rotation=0):
    if isinstance(rotation, bool) or not isinstance(rotation, Integral) or rotation not in (0, 90, 180, 270):
        raise ValueError('rotation must be 0, 90, 180 or 270 clockwise degrees')
    source = prepare_cell(image)  # Apply EXIF orientation before user rotation.
    return np.ascontiguousarray(np.rot90(source, -(rotation // 90)))


def pixel_corners(normalized, shape):
    """0 and 1 denote the first and last pixel centers, respectively."""
    try:
        points = np.asarray(normalized, dtype=np.float32)
    except (ValueError, TypeError) as exc:
        raise ValueError('Expected four normalized [x,y] corner pairs') from exc
    if points.shape != (4, 2) or not np.isfinite(points).all() or np.any(points < 0) or np.any(points > 1):
        raise ValueError('Corners must be four finite [x,y] pairs between 0 and 1')
    # Clockwise TL,TR,BR,BL in image coordinates, without crossings or reflection.
    if not cv2.isContourConvex(points) or cv2.contourArea(points, oriented=True) <= .001:
        raise ValueError('Select four distinct corners in TL,TR,BR,BL order')
    if (points[0, 0] >= points[1, 0] or points[3, 0] >= points[2, 0]
            or points[0, 1] >= points[3, 1] or points[1, 1] >= points[2, 1]):
        raise ValueError('Rotate the table upright and select TL,TR,BR,BL corners')
    h, w = shape[:2]
    return points * np.array([w - 1, h - 1], dtype=np.float32)
