import base64
import io
import json
import threading
import unittest
from http.client import HTTPConnection
from http.server import HTTPServer
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
from ocr import MarkRecognizer
from ocr.cell_extractor import extract_cells, ExtractionError
from ocr.full_table import process_table
from ocr.server import make_handler

SAMPLE = Path(__file__).resolve().parents[2] / 'assets/sample_marksheet.png'


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
    def test_sample_and_original_coordinates(self):
        cells = extract_cells(SAMPLE).cells
        self.assertEqual(len(cells),28)
        self.assertEqual((cells[0].question,cells[0].part),('1','a'))
        self.assertTrue(95 <= cells[0].bounds[0] <= 125)
        self.assertTrue(85 <= cells[0].bounds[1] <= 110)

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

    def test_missing_line_rejected(self):
        image = grid()
        image[305:316,45:556] = 255
        with self.assertRaises(ExtractionError):
            extract_cells(image)
        with self.assertRaises(ExtractionError):
            extract_cells(np.full((400,400,3),255,np.uint8))

    def test_payload_crop_and_review(self):
        payload = process_table(SAMPLE,MarkRecognizer(backend=Backend()))
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
            status,payload = post({'image_base64':base64.b64encode(SAMPLE.read_bytes()).decode(),'table_type':'5-8'})
            self.assertEqual(status,200)
            self.assertEqual(payload['questions'],['5','6','7','8'])
            self.assertEqual(sum(len(v) for v in payload['cellResults'].values()),28)
            self.assertEqual(post({'image_base64':'invalid'})[0],422)
            self.assertEqual(post({},'wrong')[0],401)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
