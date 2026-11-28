"""Perspective rectification and extraction of the OBE 5-column rubric."""
from dataclasses import dataclass
import cv2
import numpy as np
from .preprocessing import prepare_cell
from .table_processor import ExtractedCell, PARTS, TABLE_QUESTIONS

WARP_MARGIN = 96


class ExtractionError(ValueError):
    pass


@dataclass
class TableExtraction:
    image: np.ndarray
    cells: list
    corners: list
    transform: np.ndarray  # Coarse perspective transform; bounds also include the grid remap.


def _binary(image, *, faint=False):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    # Estimate paper brightness separately from ink; keep original pixels for OCR.
    background = cv2.GaussianBlur(gray, (0, 0), 25)
    gray = cv2.divide(gray, np.maximum(background, 1), scale=255)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    return cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                 cv2.THRESH_BINARY_INV, 31, 4 if faint else 12)


def _intersection(a, b):
    point = np.cross(a, b)
    if abs(point[2]) < 1e-6:
        raise ExtractionError('Table edges do not form a quadrilateral')
    return point[:2] / point[2]


# Normalized borders measured from the reference and the regular rubric.
TEMPLATES = (
    (np.array([0,115,183,252,320,379])/379,
     np.array([0,96,150,202,255,308,361,414,474,526])/526),
    (np.linspace(0,1,6),
     np.array([0,100,180,260,340,420,500,580,660,740])/740),
)


def _fit_axis(positions, ratios, span_hint, extent):
    """Register partial lines to a template, allowing outliers and missing edges."""
    positions = np.asarray(positions)
    best = None
    for i in range(len(positions)):
        for j in range(i+1,len(positions)):
            for a in range(len(ratios)):
                for b in range(a+1,len(ratios)):
                    span = (positions[j]-positions[i])/(ratios[b]-ratios[a])
                    if not .7*span_hint <= span <= 1.4*span_hint:
                        continue
                    expected = positions[i]-ratios[a]*span+ratios*span
                    # Avoid selecting an equally good but shifted fit outside
                    # the photograph when an outer border is missing.
                    if expected[0] < 0 or expected[-1] >= extent:
                        continue
                    distances = np.abs(expected[:,None]-positions)
                    errors = distances.min(axis=1)
                    matches = errors < max(4,span*.025)
                    score = int(matches.sum()) - float(np.minimum(errors/span,.08).sum())
                    score -= .2*abs(span/span_hint-1)
                    if best is None or score > best[0]:
                        best = score, expected, matches
    if best is not None:
        _, expected, matches = best
        nearest = np.abs(expected[:, None]-positions).argmin(axis=1)
        if matches.sum() >= 2:
            # Refine with all matched lines, rather than the initial pair alone.
            span, offset = np.linalg.lstsq(
                np.column_stack([ratios[matches], np.ones(matches.sum())]),
                positions[nearest[matches]], rcond=None)[0]
            refined = offset+ratios*span
            if refined[0] >= 0 and refined[-1] < extent:
                best = best[0], refined, matches
    return best


def _line_groups(lines, vertical, h, w):
    entries = []
    for x1,y1,x2,y2 in lines:
        dx,dy = x2-x1,y2-y1
        length = np.hypot(dx,dy)
        if vertical:
            if abs(dy) < .25*h or abs(dx) > .5*abs(dy):
                continue
            slope = dx/dy
            pos = x1+slope*(h/2-y1)
        else:
            if abs(dx) < .25*w or abs(dy) > .5*abs(dx):
                continue
            slope = dy/dx
            pos = y1+slope*(w/2-x1)
        entries.append((pos,slope,length))
    groups = []
    for entry in sorted(entries):
        if groups and entry[0]-groups[-1][-1][0] < max(4,min(h,w)*.008):
            groups[-1].append(entry)
        else:
            groups.append([entry])
    # Use the longest segment at each position; the Grand Total edges are short.
    representatives = [max(group,key=lambda item:item[2]) for group in groups]
    return sorted(sorted(representatives,key=lambda item:item[2],reverse=True)[:30])


def _line_candidates_binary(binary, *, deskew=True):
    h,w = binary.shape
    lines = cv2.HoughLinesP(binary,1,np.pi/720,35,
                          minLineLength=min(h,w)*.15,maxLineGap=40)
    candidates = []
    if lines is not None:
        vertical = _line_groups(lines[:,0],True,h,w)
        horizontal = _line_groups(lines[:,0],False,h,w)
        if len(vertical) >= 3 and len(horizontal) >= 4:
            width_hint = float(np.median(sorted([v[2] for v in horizontal],reverse=True)[:6]))
            height_hint = float(np.median(sorted([v[2] for v in vertical],reverse=True)[:6]))
            for xs,ys in TEMPLATES:
                xf = _fit_axis([v[0] for v in vertical],xs,width_hint,w)
                yf = _fit_axis([v[0] for v in horizontal],ys,height_hint,h)
                if xf is None or yf is None or xf[2].sum()<3 or yf[2].sum()<4:
                    continue
                def edge(groups,position,is_vertical,span):
                    nearest = min(groups,key=lambda v:abs(v[0]-position))
                    if abs(nearest[0]-position) < max(4, span*.04):
                        position, slope = nearest[:2]
                    else:
                        slope = float(np.median([v[1] for v in groups]))
                    if is_vertical:
                        return np.array([1.,-slope,slope*h/2-position])
                    return np.array([-slope,1.,slope*w/2-position])
                left,right = [edge(vertical,x,True,np.ptp(xf[1])) for x in xf[1][[0,-1]]]
                top,bottom = [edge(horizontal,y,False,np.ptp(yf[1])) for y in yf[1][[0,-1]]]
                candidates.append([_intersection(left,top),_intersection(right,top),
                                   _intersection(right,bottom),_intersection(left,bottom)])
    if deskew and lines is not None:
        segments = lines[:, 0].astype(float)
        dx, dy = segments[:, 2]-segments[:, 0], segments[:, 3]-segments[:, 1]
        angles = (np.degrees(np.arctan2(dy, dx))+45) % 90-45
        lengths = np.hypot(dx, dy)
        votes, bins = np.histogram(angles, bins=45, range=(-45, 45), weights=lengths)
        peak = (bins[int(votes.argmax())]+bins[int(votes.argmax())+1])/2
        selected = np.abs(angles-peak) < 5
        angle = float(np.average(angles[selected], weights=lengths[selected]))
        if abs(angle) > 5:
            matrix = cv2.getRotationMatrix2D((w/2, h/2), angle, 1)
            cosine, sine = abs(matrix[0, 0]), abs(matrix[0, 1])
            width, height = int(np.ceil(w*cosine+h*sine)), int(np.ceil(h*cosine+w*sine))
            matrix[:, 2] += [(width-w)/2, (height-h)/2]
            upright = cv2.warpAffine(binary, matrix, (width, height), borderValue=0)
            inverse = cv2.invertAffineTransform(matrix)
            for points in _line_candidates_binary(upright, deskew=False):
                candidates.append(cv2.transform(np.float32([points]), inverse)[0])
    return candidates


def _locate_candidates(image, binary):
    """Rank contour quadrilaterals before validating their warped grids."""
    h, w = image.shape[:2]
    # Close small breaks without erasing slanted lines as directional opening can.
    closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    contours, _ = cv2.findContours(closed, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    ranked = []
    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:80]:
        area = cv2.contourArea(contour)
        if area < max(1000, h*w*.02):
            continue
        for tolerance in (.015, .025, .04):
            polygon = cv2.approxPolyDP(contour, tolerance*cv2.arcLength(contour, True), True)
            if len(polygon) != 4 or not cv2.isContourConvex(polygon):
                continue
            points = polygon[:, 0].astype(np.float32)
            center = points.mean(axis=0)
            points = points[np.argsort(np.arctan2(points[:, 1]-center[1], points[:, 0]-center[0]))]
            points = np.roll(points, -int(np.argmin(points.sum(axis=1))), axis=0)
            # Keep the same TL,TR,BR,BL contract as the native editor.
            if (points[0,0] >= points[1,0] or points[3,0] >= points[2,0]
                    or points[0,1] >= points[3,1] or points[1,1] >= points[2,1]):
                continue
            width = (np.linalg.norm(points[1]-points[0])+np.linalg.norm(points[2]-points[3]))/2
            height = (np.linalg.norm(points[3]-points[0])+np.linalg.norm(points[2]-points[1]))/2
            ratio = width/max(height, 1)
            if not .25 < ratio < 1.5:
                continue
            rectangularity = min(area/max(cv2.contourArea(points), 1), 1)
            score = rectangularity + area/(h*w) - abs(np.log(ratio/.7))*.3
            if not any(np.max(np.linalg.norm(points-old, axis=1)) < 8 for _, old in ranked):
                ranked.append((score, points))
            break
    return [points for _, points in sorted(ranked, key=lambda item: item[0], reverse=True)]


def rectify(image, corners=None):
    if corners is None:
        h,w = image.shape[:2]
        best = None
        for faint in (False, True):
            binary = _binary(image, faint=faint)
            # A Grand Total extension can turn a contour into a false trapezoid.
            # Compare its grid with the long-line reconstruction as well.
            candidates = _locate_candidates(image, binary)+_line_candidates_binary(binary)
            for candidate in candidates:
                candidate = np.asarray(candidate)
                if (np.any(candidate < 0) or np.any(candidate[:, 0] >= w)
                        or np.any(candidate[:, 1] >= h)):
                    continue
                try:
                    corrected, points, transform = rectify(image, candidate)
                    score, _, _ = _align_template(corrected)
                except ExtractionError:
                    continue
                if best is None or score > best[0]:
                    best = score, corrected, points, transform
            if best is not None:
                break
        if best is None:
            raise ExtractionError('Could not locate the main marks table. Capture the complete table clearly.')
        return best[1:]
    points = np.asarray(corners, dtype=np.float32)
    if points.shape != (4, 2) or not np.isfinite(points).all():
        raise ExtractionError('Corners must be four finite [x,y] pairs in TL,TR,BR,BL order')
    if not cv2.isContourConvex(points) or cv2.contourArea(points) < 1000:
        raise ExtractionError('Invalid or too small table quadrilateral')
    width = int(max(np.linalg.norm(points[1]-points[0]), np.linalg.norm(points[2]-points[3])))
    height = int(max(np.linalg.norm(points[3]-points[0]), np.linalg.norm(points[2]-points[1])))
    if max(width, height) > 4000:
        raise ExtractionError('Table dimensions exceed extraction limits')
    # Curved outer borders can extend beyond their corner quadrilateral.
    width, height = 1000, 1400
    margin = WARP_MARGIN
    dest = np.float32([[margin, margin], [width+margin, margin],
                      [width+margin, height+margin], [margin, height+margin]])
    transform = cv2.getPerspectiveTransform(points, dest)
    corrected = cv2.warpPerspective(image, transform, (width+2*margin+1, height+2*margin+1), borderValue=(255,255,255))
    return corrected, points.tolist(), transform


def _positions(mask, axis, minimum):
    projection = np.count_nonzero(mask, axis=axis)
    indices = np.flatnonzero(projection >= minimum)
    groups = np.split(indices, np.flatnonzero(np.diff(indices) > 3)+1)
    return [int(round(float(g.mean()))) for g in groups if len(g)]


GRID_SAMPLES = 17


def _grid_profiles(binary, vertical):
    """Short line segments survive mild curvature; local strips avoid smearing peaks."""
    h, w = binary.shape
    thickness = np.ones((1, 7) if vertical else (7, 1), np.uint8)
    length = max(9, ((h if vertical else w)//32) | 1)
    kernel = np.ones((length, 1) if vertical else (1, length), np.uint8)
    mask = cv2.morphologyEx(cv2.dilate(binary, thickness), cv2.MORPH_OPEN, kernel)
    span = h if vertical else w
    edges = np.linspace(0, span, GRID_SAMPLES+1).astype(int)
    centers = (edges[:-1]+edges[1:]-1)/2
    profiles = []
    for start, end in zip(edges[:-1], edges[1:]):
        strip = mask[start:end, :] if vertical else mask[:, start:end]
        profiles.append(_positions(strip, 0 if vertical else 1, (end-start)*.35))
    return centers, profiles


def _trace_grid(profiles, centers, expected, span):
    tracks, count, score = [], 0, 0.
    for index, position in enumerate(expected):
        gap = min(np.diff(expected)[max(0, index-1):min(len(expected)-1, index+1)])
        radius = max(8., gap*.4)
        found = []
        predicted = position
        for candidates in profiles:
            nearest = min(candidates, key=lambda value: abs(value-predicted)) if candidates else None
            if nearest is not None and abs(nearest-predicted) < radius:
                predicted = float(nearest)
                found.append(predicted)
            else:
                found.append(np.nan)
        valid = np.isfinite(found)
        if valid.sum() >= GRID_SAMPLES*.4:
            trace = np.interp(centers, centers[valid], np.asarray(found)[valid])
            count += 1
            score += float(valid.mean()) - min(float(np.median(abs(trace-position)))/span, .08)
        else:
            trace = np.full(GRID_SAMPLES, position)
        tracks.append(trace)
    return np.asarray(tracks), count, score


def _align_grid(corrected, *, manual=False):
    """Register the rubric, following each visible boundary across the photograph."""
    for faint in (False, True):
        binary = _binary(corrected, faint=faint)
        h,w = binary.shape
        sample_y, vertical = _grid_profiles(binary, True)
        sample_x, horizontal = _grid_profiles(binary, False)
        best = None
        for xr,yr in TEMPLATES:
            xs, ys = WARP_MARGIN+xr*(w-2*WARP_MARGIN-1), WARP_MARGIN+yr*(h-2*WARP_MARGIN-1)
            vx, nx, sx = _trace_grid(vertical, sample_y, xs, w-2*WARP_MARGIN-1)
            hy, ny, sy = _trace_grid(horizontal, sample_x, ys, h-2*WARP_MARGIN-1)
            if np.min(np.diff(vx, axis=0)) < 15 or np.min(np.diff(hy, axis=0)) < 15:
                continue
            if ((manual and faint) or (nx>=3 and ny>=4)) and (best is None or sx+sy>best[0]):
                best = sx+sy, xs, ys, vx, hy, sample_x, sample_y
        if best is not None:
            return best
    raise ExtractionError('Insufficient evidence to localize the main marks table.')


def _align_template(corrected, *, manual=False):
    score, xs, ys, *_ = _align_grid(corrected, manual=manual)
    return score, np.rint(xs).astype(int).tolist(), np.rint(ys).astype(int).tolist()


def _straighten_grid(corrected, *, manual=False):
    """Flatten moderate paper bends using the traced horizontal and vertical grid."""
    _, xs, ys, vx, hy, sample_x, sample_y = _align_grid(corrected, manual=manual)
    h, w = corrected.shape[:2]
    x, y = np.arange(w), np.arange(h)
    vertical = np.array([np.interp(y, sample_y, trace) for trace in vx])
    horizontal = np.array([np.interp(x, sample_x, trace) for trace in hy])
    base_x = np.array([np.interp(x, xs, vertical[:, row]) for row in range(h)], np.float32)
    base_y = np.array([np.interp(y, ys, horizontal[:, col]) for col in range(w)], np.float32).T.copy()
    identity_x, identity_y = np.meshgrid(x.astype(np.float32), y.astype(np.float32))
    map_x, map_y = base_x, base_y
    # Account for bends in both directions without treating the sheet as one plane.
    for _ in range(2):
        map_y = cv2.remap(base_y, map_x, identity_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        map_x = cv2.remap(base_x, identity_x, map_y, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    flat = cv2.remap(corrected, map_x, map_y, cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_CONSTANT, borderValue=(255,255,255))
    return flat, np.rint(xs).astype(int), np.rint(ys).astype(int), map_x, map_y


def detect_corners(image):
    """Locate only; do not load the recognizer or run OCR."""
    source = prepare_cell(image)
    h, w = source.shape[:2]
    scale = min(1., 2000 / max(h, w))
    working = cv2.resize(source, None, fx=scale, fy=scale) if scale < 1 else source
    _, points, _ = rectify(working)
    points = np.asarray(points) / scale
    # Line fitting can extrapolate a few pixels past a photographed border.
    # Snap only this small tolerance; larger excursions need manual selection.
    extent = np.array([w - 1, h - 1])
    if np.any(points < -.02 * extent) or np.any(points > 1.02 * extent):
        raise ExtractionError('The table reaches outside the photograph. Adjust the corners or retake the photo.')
    return (np.clip(points, 0, extent) / extent).tolist()


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
    # User-supplied corners establish the main rectangle even when borders are
    # too faint for automatic localization. Visible lines still refine it.
    corrected, xs, ys, map_x, map_y = _straighten_grid(corrected, manual=corners is not None)
    if min(np.diff(xs)) < 15 or min(np.diff(ys)) < 15:
        raise ExtractionError('Cells are too small to read reliably')
    cells = []
    inverse = np.linalg.inv(transform)
    for row, part in enumerate(PARTS, start=1):
        for column, question in enumerate(TABLE_QUESTIONS[table_type], start=1):
            x1,x2,y1,y2 = xs[column],xs[column+1],ys[row],ys[row+1]
            pad = max(3, int(min(x2-x1,y2-y1)*.07))
            crop = corrected[y1+pad:y2-pad, x1+pad:x2-pad].copy()
            # Curved edges can have extrema between corners; include the full perimeter.
            edge_x = np.concatenate([map_x[y1,x1:x2+1],map_x[y2,x1:x2+1],map_x[y1:y2+1,x1],map_x[y1:y2+1,x2]])
            edge_y = np.concatenate([map_y[y1,x1:x2+1],map_y[y2,x1:x2+1],map_y[y1:y2+1,x1],map_y[y1:y2+1,x2]])
            polygon = cv2.perspectiveTransform(np.float32([np.column_stack([edge_x,edge_y])]), inverse)[0]
            bounds = (int(polygon[:,0].min()), int(polygon[:,1].min()),
                      int(polygon[:,0].max()), int(polygon[:,1].max()))
            cells.append(ExtractedCell(question, part, crop, max_mark, bounds))
    return TableExtraction(corrected, cells, points, transform)
