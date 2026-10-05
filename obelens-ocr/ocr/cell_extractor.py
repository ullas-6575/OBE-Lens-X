"""Perspective rectification and extraction of the OBE 5-column rubric."""
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


# Normalized borders measured from the reference and the regular rubric.
TEMPLATES = (
    (np.array([0,115,183,252,320,379])/379,
     np.array([0,96,150,202,255,308,361,414,474,526])/526),
    (np.linspace(0,1,6),
     np.array([0,100,180,260,340,420,500,580,660,740])/740),
)


def _fit_axis(positions, ratios, span_hint):
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
                    distances = np.abs(expected[:,None]-positions)
                    errors = distances.min(axis=1)
                    matches = errors < max(4,span*.025)
                    score = int(matches.sum()) - float(np.minimum(errors/span,.08).sum())
                    score -= .2*abs(span/span_hint-1)
                    if best is None or score > best[0]:
                        best = score, expected, matches
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


def _locate_candidates(image):
    h,w = image.shape[:2]
    binary = _binary(image)
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
                xf = _fit_axis([v[0] for v in vertical],xs,width_hint)
                yf = _fit_axis([v[0] for v in horizontal],ys,height_hint)
                if xf is None or yf is None or xf[2].sum()<3 or yf[2].sum()<4:
                    continue
                def edge(groups,position,is_vertical):
                    nearest = min(groups,key=lambda v:abs(v[0]-position))
                    slope = nearest[1] if abs(nearest[0]-position)<10 else float(np.median([v[1] for v in groups]))
                    if is_vertical:
                        return np.array([1.,-slope,slope*h/2-position])
                    return np.array([-slope,1.,slope*w/2-position])
                left,right = [edge(vertical,x,True) for x in xf[1][[0,-1]]]
                top,bottom = [edge(horizontal,y,False) for y in yf[1][[0,-1]]]
                candidates.append([_intersection(left,top),_intersection(right,top),
                                   _intersection(right,bottom),_intersection(left,bottom)])
    # Connected outer contours are a fallback when individual edges fragment.
    closed = cv2.morphologyEx(binary,cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))
    contours,_ = cv2.findContours(closed,cv2.RETR_LIST,cv2.CHAIN_APPROX_SIMPLE)
    for contour in sorted(contours,key=cv2.contourArea,reverse=True)[:20]:
        if cv2.contourArea(contour) < h*w*.08:
            continue
        polygon = cv2.approxPolyDP(contour,.025*cv2.arcLength(contour,True),True)
        if len(polygon)==4 and cv2.isContourConvex(polygon):
            points = polygon[:,0].astype(np.float32)
            center = points.mean(axis=0)
            points = points[np.argsort(np.arctan2(points[:,1]-center[1],points[:,0]-center[0]))]
            points = np.roll(points,-int(np.argmin(points.sum(axis=1))),axis=0)
            candidates.append(points)
    return candidates


def rectify(image, corners=None):
    if corners is None:
        h,w = image.shape[:2]
        best = None
        for candidate in _locate_candidates(image):
            try:
                candidate = np.asarray(candidate)
                if (candidate[:,0].min() < -w*.05 or candidate[:,0].max() > w*1.05
                        or candidate[:,1].min() < -h*.05 or candidate[:,1].max() > h*1.05):
                    continue
                corrected,points,transform = rectify(image,candidate)
                score,_,_ = _align_template(corrected)
            except ExtractionError:
                continue
            if best is None or score > best[0]:
                best = score,corrected,points,transform
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
    # White margin keeps transformed outside borders measurable.
    width, height = 1000, 1400
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


def _align_template(corrected):
    """Choose a known layout using aggregate evidence, then snap visible borders."""
    binary = _binary(corrected)
    h,w = binary.shape
    v = cv2.morphologyEx(binary,cv2.MORPH_OPEN,np.ones((h//8,1),np.uint8))
    hor = cv2.morphologyEx(binary,cv2.MORPH_OPEN,np.ones((1,w//8),np.uint8))
    detected_x = _positions(v,0,h*.35)
    detected_y = _positions(hor,1,w*.35)
    best = None
    for xr,yr in TEMPLATES:
        axes = []
        score = 0.
        counts = []
        for detected,ratios,extent in [(detected_x,xr,w),(detected_y,yr,h)]:
            expected = 8+ratios*(extent-17)
            borders = expected.copy()
            matches = 0
            for index,position in enumerate(expected):
                if detected:
                    nearest = min(detected,key=lambda value:abs(value-position))
                    error = abs(nearest-position)/(extent-17)
                    if error < .035:
                        matches += 1
                        score += 1-error/.035
                        borders[index] = nearest
            axes.append(np.rint(borders).astype(int).tolist())
            counts.append(matches)
        # This validates localization, rather than requiring every internal line.
        if counts[0]>=3 and counts[1]>=4 and (best is None or score>best[0]):
            best = score,*axes
    if best is None:
        raise ExtractionError('Insufficient evidence to localize the main marks table.')
    return best


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
    _,xs,ys = _align_template(corrected)
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
