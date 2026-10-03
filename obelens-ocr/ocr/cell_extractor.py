"""Perspective rectification and strict extraction of the OBE 5-column rubric."""
from dataclasses import dataclass
import cv2
import numpy as np
from .preprocessing import prepare_cell
from .table_processor import ExtractedCell, PARTS, TABLE_QUESTIONS


class ExtractionError(ValueError):
    pass


@dataclass
class TableExtraction:
    image: np.ndarray
    cells: list
    corners: list
    transform: np.ndarray


def _binary(image):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    return cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                 cv2.THRESH_BINARY_INV, 31, 12)


def _intersection(a, b):
    point = np.cross(a, b)
    if abs(point[2]) < 1e-6:
        raise ExtractionError('Table edges do not form a quadrilateral')
    return point[:2] / point[2]


def rectify(image, corners=None):
    if corners is None:
        h, w = image.shape[:2]
        lines = cv2.HoughLinesP(_binary(image), 1, np.pi / 720, 60,
                                minLineLength=min(h, w) * .4, maxLineGap=25)
        if lines is None:
            raise ExtractionError('No ruled table found. Include all table borders.')
        vertical, horizontal = [], []
        for x1, y1, x2, y2 in lines[:, 0]:
            dx, dy = x2 - x1, y2 - y1
            line = np.cross([x1, y1, 1], [x2, y2, 1]).astype(float)
            if abs(dy) > .55 * h and abs(dx) < .45 * abs(dy):
                vertical.append(((x1 + x2) / 2, line))
            if abs(dx) > .5 * w and abs(dy) < .45 * abs(dx):
                horizontal.append(((y1 + y2) / 2, line))
        if len(vertical) < 2 or len(horizontal) < 2:
            raise ExtractionError('Cannot locate complete table edges; use a tighter upright crop or explicit corners.')
        left, right = min(vertical, key=lambda x: x[0])[1], max(vertical, key=lambda x: x[0])[1]
        top, bottom = min(horizontal, key=lambda x: x[0])[1], max(horizontal, key=lambda x: x[0])[1]
        corners = [_intersection(left, top), _intersection(right, top),
                   _intersection(right, bottom), _intersection(left, bottom)]
    points = np.asarray(corners, dtype=np.float32)
    if points.shape != (4, 2) or not np.isfinite(points).all():
        raise ExtractionError('Corners must be four finite [x,y] pairs in TL,TR,BR,BL order')
    if not cv2.isContourConvex(points) or cv2.contourArea(points) < 1000:
        raise ExtractionError('Invalid or too small table quadrilateral')
    width = int(max(np.linalg.norm(points[1]-points[0]), np.linalg.norm(points[2]-points[3])))
    height = int(max(np.linalg.norm(points[3]-points[0]), np.linalg.norm(points[2]-points[1])))
    if max(width, height) > 4000:
        raise ExtractionError('Table dimensions exceed extraction limits')
    # White margin keeps transformed outside borders measurable.
    margin = 8
    dest = np.float32([[margin, margin], [width+margin, margin],
                      [width+margin, height+margin], [margin, height+margin]])
    transform = cv2.getPerspectiveTransform(points, dest)
    corrected = cv2.warpPerspective(image, transform, (width+17, height+17), borderValue=(255,255,255))
    return corrected, points.tolist(), transform


def _positions(mask, axis, minimum):
    projection = np.count_nonzero(mask, axis=axis)
    indices = np.flatnonzero(projection >= minimum)
    groups = np.split(indices, np.flatnonzero(np.diff(indices) > 3)+1)
    return [int(round(float(g.mean()))) for g in groups if len(g)]


def extract_cells(image, *, table_type='1-4', corners=None, max_mark=None):
    if table_type not in TABLE_QUESTIONS:
        raise ValueError('table_type must be 1-4 or 5-8')
    source = prepare_cell(image)
    # Limit processing while keeping coordinates in the original input space.
    scale = min(1., 2000 / max(source.shape[:2]))
    working = cv2.resize(source, None, fx=scale, fy=scale) if scale < 1 else source
    scaled_corners = np.asarray(corners)*scale if corners is not None else None
    corrected, points, transform = rectify(working, scaled_corners)
    transform = transform @ np.diag([scale, scale, 1.])
    points = (np.asarray(points)/scale).tolist()
    binary = _binary(corrected)
    h,w = binary.shape
    v = cv2.morphologyEx(binary, cv2.MORPH_OPEN, np.ones((max(15,h//5),1),np.uint8))
    hor = cv2.morphologyEx(binary, cv2.MORPH_OPEN, np.ones((1,max(15,w//5)),np.uint8))
    xs = _positions(v, 0, h*.65)
    ys = _positions(hor, 1, w*.6)
    # Header + seven parts + total. Never guess missing lines or column identities.
    if len(xs) != 6 or len(ys) != 10:
        raise ExtractionError(f'Expected 6 vertical and 10 horizontal borders; found {len(xs)} and {len(ys)}. Capture one complete rubric table.')
    if min(np.diff(xs)) < 15 or min(np.diff(ys)) < 15:
        raise ExtractionError('Cells are too small to read reliably')
    cells = []
    inverse = np.linalg.inv(transform)
    for row, part in enumerate(PARTS, start=1):
        for column, question in enumerate(TABLE_QUESTIONS[table_type], start=1):
            x1,x2,y1,y2 = xs[column],xs[column+1],ys[row],ys[row+1]
            pad = max(3, int(min(x2-x1,y2-y1)*.07))
            crop = corrected[y1+pad:y2-pad, x1+pad:x2-pad].copy()
            polygon = cv2.perspectiveTransform(np.float32([[[x1,y1],[x2,y1],[x2,y2],[x1,y2]]]), inverse)[0]
            bounds = (int(polygon[:,0].min()), int(polygon[:,1].min()),
                      int(polygon[:,0].max()), int(polygon[:,1].max()))
            cells.append(ExtractedCell(question, part, crop, max_mark, bounds))
    return TableExtraction(corrected, cells, points, transform)
