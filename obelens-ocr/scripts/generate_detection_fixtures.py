"""Generate shared images and Linux results for the actual Android detector tests.

Expected synthetic corners are checked against independent ground truth before
writing Linux results. No recognizer/model is needed. Run through detector-tests.
"""
import sys
from pathlib import Path
import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ocr.cell_extractor import detect_corners, extract_cells, ExtractionError


def bend(image, horizontal=32, vertical=20):
    y, x = np.indices(image.shape[:2], dtype=np.float32)
    map_x = x-vertical*np.sin(np.pi*(y-50)/740)
    map_y = y-horizontal*np.sin(np.pi*(x-50)/500)
    return cv2.remap(image, map_x, map_y, cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_CONSTANT, borderValue=(255,255,255))


def rotate(image, corners, angle):
    h,w = image.shape[:2]
    matrix = cv2.getRotationMatrix2D((w/2,h/2), angle, 1)
    cosine,sine = abs(matrix[0,0]),abs(matrix[0,1])
    width,height = int(np.ceil(w*cosine+h*sine)),int(np.ceil(h*cosine+w*sine))
    matrix[:,2] += [(width-w)/2,(height-h)/2]
    image = cv2.warpAffine(image, matrix, (width,height), borderValue=(255,255,255))
    return image, cv2.transform(np.float32([corners]), matrix)[0]


def faint_grid(line_shade=200):
    """Thin gray printing on dim paper, with the attached Grand Total box."""
    image = np.full((850,650,3),220,np.uint8)
    for x in [50,190,280,370,460,550]:
        cv2.line(image,(x,50),(x,790),(line_shade,)*3,1)
    for y in [50,185,260,335,410,485,560,635,710,790]:
        cv2.line(image,(50,y),(550,y),(line_shade,)*3,1)
    cv2.rectangle(image,(550,710),(625,790),(line_shade,)*3,1)
    cv2.putText(image,'15',(205,240),cv2.FONT_HERSHEY_SIMPLEX,.7,(55,55,55),1)
    y,x = np.indices(image.shape[:2])
    image = np.clip(image*(.45+.4*x/650)[:,:,None],0,255).astype(np.uint8)
    image = cv2.GaussianBlur(image,(3,3),.6)
    return image, np.float32([[50,50],[550,50],[550,790],[50,790]])


def fixtures():
    grid = np.full((850, 650, 3), 255, np.uint8)
    corners = np.float32([[50,50],[550,50],[550,790],[50,790]])
    for x in [50,150,250,350,450,550]:
        cv2.line(grid, (x,50), (x,790), (0,0,0), 2)
    for y in [50,150,230,310,390,470,550,630,710,790]:
        cv2.line(grid, (50,y), (550,y), (0,0,0), 2)
    cv2.putText(grid, '15', (165,210), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0,0,0), 2)
    yield 'intact', grid, corners
    target = np.float32([[100,55],[590,95],[545,805],[50,770]])
    transform = cv2.getPerspectiveTransform(corners, target)
    def warp(image):
        return cv2.warpPerspective(image, transform, (650,850), borderValue=(255,255,255))
    yield 'perspective', warp(grid), target
    partial = grid.copy()
    partial[45:56,45:556] = 255
    partial[45:796,545:556] = 255
    yield 'broken_outer_borders', partial, corners
    yield 'broken_borders_perspective', warp(partial), target
    extension = grid.copy()
    cv2.rectangle(extension, (550,630), (635,790), (0,0,0), 2)
    extension[45:796,545:556] = 255
    extension[45:56,45:640] = 255
    extension[305:316,45:556] = 255
    yield 'grand_total_extension', extension, corners
    missing = grid.copy()
    for y in [310,470]:
        missing[y-5:y+6,45:556] = 255
    for x in [250,450]:
        missing[45:796,x-5:x+6] = 255
    yield 'missing_internal_lines', missing, corners
    noise = np.random.default_rng(42).normal(0, 5, grid.shape)
    shaded = np.clip(grid*np.linspace(.5,1.,650)[None,:,None]+noise,0,255).astype(np.uint8)
    yield 'shadow_noise', shaded, corners
    page = np.full((1800,1400,3),255,np.uint8)
    cv2.rectangle(page,(20,20),(1380,1780),(0,0,0),3)
    page[500:925,600:925] = cv2.resize(grid,(325,425),interpolation=cv2.INTER_AREA)
    yield 'small_table_page_border', page, corners*.5+[600,500]
    for factor in [3,4]:
        yield f'camera_size_{factor}', cv2.resize(grid,None,fx=factor,fy=factor), corners*factor
    # Deterministic JPEG artifacts exercise the same decoded image in both cores.
    _, encoded = cv2.imencode('.jpg', shaded, [cv2.IMWRITE_JPEG_QUALITY,65])
    yield 'jpeg_shadow', cv2.imdecode(encoded,cv2.IMREAD_COLOR), corners
    for angle in [-35, 32]:
        tilted, points = rotate(partial, corners, angle)
        yield f'rotated_broken_{angle}', tilted, points
    curved = bend(grid)
    yield 'curved_grid', curved, corners
    tilted, points = rotate(curved, corners, 24)
    yield 'curved_rotated', tilted, points
    y,x = np.indices(grid.shape[:2])
    illumination = .3+.6*x/650-.2*np.exp(-((x-220)**2+(y-350)**2)/40000)
    yield 'uneven_illumination', np.clip(grid*illumination[:,:,None],0,255).astype(np.uint8), corners
    attached, points = faint_grid(80)
    yield 'attached_grand_total', attached, points
    faint, points = faint_grid()
    yield 'faint_thin_grid', faint, points
    tilted, points = rotate(faint, points, 12)
    yield 'faint_rotated_grid', tilted, points
    captured = cv2.imread(str(Path(__file__).resolve().parents[1]/'tests/fixtures/answer_table_q5_q8.jpg'))
    yield 'captured_q5_q8', captured, np.float32([[137,184],[944,165],[984,1336],[117,1339]])
    perspective = cv2.imread(str(Path(__file__).resolve().parents[1]/'tests/fixtures/answer_table_perspective.jpg'))
    yield 'captured_perspective', perspective, np.float32([[178,467],[851,455],[918,1469],[133,1484]])
    blank = np.full((400,400,3),255,np.uint8)
    yield 'blank_reject', blank, False
    rectangle = blank.copy()
    cv2.rectangle(rectangle,(40,40),(360,360),(0,0,0),2)
    yield 'page_only_reject', rectangle, False


def main():
    directory = Path(sys.argv[1])
    directory.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name, image, truth in fixtures():
        try:
            result = np.array(detect_corners(image))
        except ExtractionError:
            result = None
        if truth is False:
            assert result is None, f'{name}: expected manual fallback'
        else:
            assert result is not None, f'{name}: Linux failed detection'
            if truth is not None:
                actual = result * [image.shape[1]-1,image.shape[0]-1]
                # A bent photographed border is not exactly a straight quadrilateral.
                tolerance = 28 if name == 'captured_q5_q8' else 14
                np.testing.assert_allclose(actual, truth, atol=tolerance, err_msg=name)
        cv2.imwrite(str(directory/f'{name}.png'), image)
        if result is not None:
            extraction = extract_cells(image, corners=result*[image.shape[1]-1,image.shape[0]-1])
            for index, cell in enumerate(extraction.cells):
                cv2.imwrite(str(directory/f'{name}_cell_{index}.png'), cell.image)
        encoded = 'none' if result is None else ','.join(str(x) for x in result.flatten())
        manifest.append(f'{name}\t{encoded}')
    (directory/'expected.tsv').write_text('\n'.join(manifest)+'\n')
    print(f'Generated {len(manifest)} fixtures; Linux ground-truth checks passed.')


if __name__ == '__main__':
    main()
