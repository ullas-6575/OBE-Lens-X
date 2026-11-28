import base64
import io
import json
import threading
import unittest
from pathlib import Path
from http.client import HTTPConnection
from http.server import HTTPServer
import cv2
import numpy as np
from PIL import Image
from ocr import MarkRecognizer
from ocr.cell_extractor import detect_corners, extract_cells, ExtractionError
from ocr.full_table import process_table
from ocr.server import make_handler
from scripts.generate_detection_fixtures import bend, rotate, faint_grid

def grid():
    image = np.full((850,650,3),255,np.uint8)
    for x in [50,150,250,350,450,550]:
        cv2.line(image,(x,50),(x,790),(0,0,0),2)
    for y in [50,150,230,310,390,470,550,630,710,790]:
        cv2.line(image,(50,y),(550,y),(0,0,0),2)
    cv2.putText(image,'15',(165,210),cv2.FONT_HERSHEY_SIMPLEX,1.2,(0,0,0),2)
    return image


class Backend:
    def predict(self, **kwargs):
        return [{'rec_text':'15','rec_score':.3}]


class ExtractionTests(unittest.TestCase):
    def test_captured_table_excludes_extension_and_preserves_cell_positions(self):
        image = cv2.imread(str(Path(__file__).parent/'fixtures/answer_table_q5_q8.jpg'))
        corners = np.asarray(detect_corners(image))*[image.shape[1]-1,image.shape[0]-1]
        np.testing.assert_allclose(corners,[[137,184],[944,165],[984,1336],[117,1339]],atol=28)
        cells = extract_cells(image,table_type='5-8').cells
        self.assertEqual(len(cells),28)
        # Independently measured centers in the supplied photo, including blank cells.
        for row, y in enumerate([425,545,660,775,895,1015,1145]):
            for column, x in enumerate([445,600,755,900]):
                cell = cells[row*4+column]
                self.assertEqual((cell.question,cell.part),(str(5+column),'abcdefg'[row]))
                left,top,right,bottom = cell.bounds
                self.assertTrue(left < x < right and top < y < bottom,
                                f'Q{cell.question}{cell.part}: {cell.bounds}')
                self.assertLess(right,1000)  # Grand Total starts beyond the main Q8 border.

    def test_faint_grid_excludes_grand_total_and_preserves_first_mark(self):
        for shade in (80,200):
            image, corners = faint_grid(shade)
            for angle in (0,12):
                with self.subTest(shade=shade,angle=angle):
                    tilted, expected = rotate(image,corners,angle)
                    actual = np.asarray(detect_corners(tilted))*[tilted.shape[1]-1,tilted.shape[0]-1]
                    np.testing.assert_allclose(actual,expected,atol=14)
                    cells = extract_cells(tilted,table_type='5-8').cells
                    self.assertEqual(len(cells),28)
                    self.assertEqual((cells[0].question,cells[0].part),('5','a'))
                    self.assertGreater(np.count_nonzero(cells[0].image<90),50)
                    for cell in cells[1:]:
                        self.assertEqual(np.count_nonzero(cell.image<90),0)

    def test_rotated_broken_grid_preserves_cell_identities(self):
        image = grid()
        image[45:56,45:556] = 255
        image[45:796,545:556] = 255
        corners = np.float32([[50,50],[550,50],[550,790],[50,790]])
        for angle in (-35,32):
            with self.subTest(angle=angle):
                tilted, expected = rotate(image, corners, angle)
                actual = np.asarray(detect_corners(tilted))*[tilted.shape[1]-1,tilted.shape[0]-1]
                np.testing.assert_allclose(actual,expected,atol=14)
                cells = extract_cells(tilted,table_type='5-8').cells
                self.assertEqual((cells[0].question,cells[0].part),('5','a'))
                self.assertGreater(np.count_nonzero(cells[0].image<100),100)

    def test_curved_grid_is_straightened_before_cropping(self):
        curved = bend(grid())
        for manual in (False,True):
            with self.subTest(manual=manual):
                extraction = extract_cells(curved, corners=[[50,50],[550,50],[550,790],[50,790]] if manual else None)
                self.assertEqual(len(extraction.cells),28)
                self.assertGreater(np.count_nonzero(extraction.cells[0].image<100),100)
                for cell in extraction.cells[1:]:
                    self.assertLess(np.count_nonzero(cell.image<100),30)

    def test_curved_rotated_table_keeps_all_28_marks_in_their_cells(self):
        image = grid()
        for row in range(7):
            for column in range(4):
                center = (240+100*column,190+80*row)
                color = (30+20*row,40+40*column,120)
                cv2.rectangle(image,(center[0]-4,center[1]-10),(center[0]+4,center[1]+10),color,-1)
        image,_ = rotate(bend(image),np.float32([[50,50],[550,50],[550,790],[50,790]]),24)
        extraction = extract_cells(image,table_type='5-8')
        for cell in extraction.cells:
            row,column = ord(cell.part)-ord('a'),int(cell.question)-5
            color = np.array([30+20*row,40+40*column,120])
            matching = np.max(abs(cell.image.astype(int)-color),axis=2)<10
            self.assertGreater(np.count_nonzero(matching),300,f'Q{cell.question}{cell.part} lost its mark')

    def test_grid_and_original_coordinates(self):
        cells = extract_cells(grid()).cells
        self.assertEqual(len(cells),28)
        self.assertEqual((cells[0].question,cells[0].part),('1','a'))
        np.testing.assert_allclose(cells[0].bounds, [150,150,250,230], atol=2)

    def test_perspective_and_mapping(self):
        source = np.float32([[50,50],[550,50],[550,790],[50,790]])
        target = np.float32([[100,55],[590,95],[545,805],[50,770]])
        transform = cv2.getPerspectiveTransform(source,target)
        skewed = cv2.warpPerspective(grid(),transform,(650,850),borderValue=(255,255,255))
        cells = extract_cells(skewed,table_type='5-8').cells
        self.assertEqual(len(cells),28)
        self.assertEqual((cells[0].question,cells[0].part),('5','a'))
        self.assertGreater(np.count_nonzero(cells[0].image < 100),100)
        self.assertEqual(np.count_nonzero(cells[1].image < 100),0)
        self.assertEqual(len(extract_cells(skewed,corners=target).cells),28)

    def test_missing_internal_lines_are_inferred(self):
        image = grid()
        image[305:316,45:556] = 255
        image[465:476,45:556] = 255
        image[45:796,245:256] = 255
        image[45:796,445:456] = 255
        cells = extract_cells(image).cells
        self.assertEqual(len(cells),28)
        reference = extract_cells(grid()).cells
        for actual, expected in zip(cells, reference):
            np.testing.assert_allclose(actual.bounds, expected.bounds, atol=4)
        self.assertGreater(np.count_nonzero(cells[0].image < 100),100)
        self.assertEqual(np.count_nonzero(cells[1].image < 100),0)

    def test_partial_edges_and_grand_total_extension(self):
        image = grid()
        cv2.rectangle(image,(550,630),(635,790),(0,0,0),2)
        image[45:796,545:556] = 255
        image[45:56,45:640] = 255
        image[305:316,45:556] = 255
        cells = extract_cells(image,table_type='5-8').cells
        self.assertEqual(len(cells),28)
        reference = extract_cells(grid(),table_type='5-8').cells
        for actual,expected in zip(cells,reference):
            np.testing.assert_allclose(actual.bounds,expected.bounds,atol=8)
        self.assertGreater(np.count_nonzero(cells[0].image < 100),100)

    def test_extra_internal_line_is_not_fatal(self):
        image = grid()
        image[305:316,45:556] = 255
        cv2.line(image,(50,280),(550,280),(0,0,0),2)
        self.assertEqual(len(extract_cells(image).cells),28)

    def test_absent_or_unrelated_geometry_rejected(self):
        blank = np.full((400,400,3),255,np.uint8)
        rectangle = blank.copy()
        cv2.rectangle(rectangle,(40,40),(360,360),(0,0,0),2)
        for image in [blank,rectangle]:
            with self.assertRaises(ExtractionError):
                extract_cells(image)

    def test_partial_grid_under_perspective(self):
        image = grid()
        image[45:56,45:556] = 255
        image[45:796,545:556] = 255
        source = np.float32([[50,50],[550,50],[550,790],[50,790]])
        target = np.float32([[100,55],[590,95],[545,805],[50,770]])
        transform = cv2.getPerspectiveTransform(source,target)
        skewed = cv2.warpPerspective(image,transform,(650,850),borderValue=(255,255,255))
        cells = extract_cells(skewed).cells
        self.assertEqual(len(cells),28)
        self.assertGreater(np.count_nonzero(cells[0].image < 100),100)
        expected = cv2.perspectiveTransform(np.float32([[[150,150],[250,150],
                                                        [250,230],[150,230]]]),transform)[0]
        bounds = [expected[:,0].min(),expected[:,1].min(),
                  expected[:,0].max(),expected[:,1].max()]
        np.testing.assert_allclose(cells[0].bounds,bounds,atol=12)

    def test_small_table_inside_larger_page_border(self):
        image = np.full((1800, 1400, 3), 255, np.uint8)
        cv2.rectangle(image, (20, 20), (1380, 1780), (0, 0, 0), 3)
        small = cv2.resize(grid(), (325, 425), interpolation=cv2.INTER_AREA)
        image[500:925, 600:925] = small
        points = np.asarray(detect_corners(image)) * [1399, 1799]
        np.testing.assert_allclose(points, [[625,525],[875,525],[875,895],[625,895]], atol=5)

    def test_uneven_illumination_and_sensor_noise(self):
        image = grid().astype(np.float32)
        shading = np.linspace(.5, 1., image.shape[1])[None, :, None]
        noise = np.random.default_rng(42).normal(0, 5, image.shape)
        image = np.clip(image*shading+noise, 0, 255).astype(np.uint8)
        points = np.asarray(detect_corners(image)) * [649, 849]
        np.testing.assert_allclose(points, [[50,50],[550,50],[550,790],[50,790]], atol=5)

    def test_payload_crop_and_review(self):
        payload = process_table(grid(),MarkRecognizer(backend=Backend()))
        self.assertFalse(payload['isVerified'])
        cell = payload['cellResults']['1']['a']
        self.assertTrue(cell['needs_review'])
        image = Image.open(io.BytesIO(base64.b64decode(cell['crop_base64'])))
        self.assertGreater(image.width,10)


class ApiTests(unittest.TestCase):
    def test_upload_and_errors(self):
        server = HTTPServer(('127.0.0.1',0),make_handler(MarkRecognizer(backend=Backend()),'test-token'))
        thread = threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        def post(body,token='test-token'):
            connection = HTTPConnection('127.0.0.1',server.server_port)
            try:
                connection.request('POST','/ocr/table',json.dumps(body),{'Authorization':f'Bearer {token}'})
                response = connection.getresponse()
                return response.status,json.loads(response.read())
            finally:
                connection.close()
        try:
            _, encoded = cv2.imencode('.png', grid())
            status,payload = post({'image_base64':base64.b64encode(encoded).decode(),'table_type':'5-8'})
            self.assertEqual(status,200)
            self.assertEqual(payload['questions'],['5','6','7','8'])
            self.assertEqual(sum(len(v) for v in payload['cellResults'].values()),28)
            self.assertEqual(post({'image_base64':'invalid'})[0],422)
            # A valid JPEG header with truncated pixels must be an upload error,
            # not an inference/model-installation failure.
            encoded = io.BytesIO()
            Image.fromarray(grid()).save(encoded, format='JPEG')
            truncated = encoded.getvalue()[:-100]
            self.assertEqual(post({'image_base64': base64.b64encode(truncated).decode()})[0], 422)
            self.assertEqual(post({},'wrong')[0],401)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
