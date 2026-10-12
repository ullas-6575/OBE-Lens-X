"""Generate shared images and Linux results for the actual Android detector tests.

Expected synthetic corners are checked against independent ground truth before
writing Linux results. No recognizer/model is needed. Run through detector-tests.
"""
import sys
from pathlib import Path
import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ocr.cell_extractor import detect_corners, ExtractionError


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
    sample = Path(__file__).resolve().parents[2]/'assets/sample_marksheet.png'
    yield 'reference_sheet', cv2.imread(str(sample)), None
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
                np.testing.assert_allclose(actual, truth, atol=14, err_msg=name)
        cv2.imwrite(str(directory/f'{name}.png'), image)
        encoded = 'none' if result is None else ','.join(str(x) for x in result.flatten())
        manifest.append(f'{name}\t{encoded}')
    (directory/'expected.tsv').write_text('\n'.join(manifest)+'\n')
    print(f'Generated {len(manifest)} fixtures; Linux ground-truth checks passed.')


if __name__ == '__main__':
    main()
