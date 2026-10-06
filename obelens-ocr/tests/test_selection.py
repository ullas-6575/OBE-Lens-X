import base64
import io
import json
import threading
import unittest
from http.client import HTTPConnection
from http.server import HTTPServer
from unittest.mock import patch
import cv2
import numpy as np
from PIL import Image
from ocr import MarkRecognizer
from ocr.cell_extractor import detect_corners, extract_cells
from ocr.full_table import process_table
from ocr.server import make_handler
from ocr.table_selection import orient_image, pixel_corners
from test_table import grid, Backend, SAMPLE


class SelectionTests(unittest.TestCase):
    def test_detection_round_trip_preserves_question_and_cell_mapping(self):
        image = grid()
        normalized = detect_corners(image)
        points = pixel_corners(normalized, image.shape)
        automatic = extract_cells(image, table_type='5-8').cells
        manual = extract_cells(image, table_type='5-8', corners=points).cells
        for actual, expected in zip(manual, automatic):
            self.assertEqual((actual.question, actual.part), (expected.question, expected.part))
            np.testing.assert_allclose(actual.bounds, expected.bounds, atol=2)
        self.assertGreater(np.count_nonzero(manual[0].image < 100), 100)
        self.assertEqual(np.count_nonzero(manual[1].image < 100), 0)

    def test_all_user_rotations_actually_rotate_pixels_before_cropping(self):
        upright = grid()
        normalized = (np.float32([[50,50],[550,50],[550,790],[50,790]]) / [649,849]).tolist()
        for rotation in (0, 90, 180, 270):
            sideways = np.ascontiguousarray(np.rot90(upright, rotation // 90))
            result = process_table(sideways, MarkRecognizer(backend=Backend()),
                                   rotation=rotation, normalized_corners=normalized, table_type='5-8')
            self.assertEqual(result['rotation'], rotation)
            self.assertEqual(result['cellMarks']['5']['a'], '15')
            self.assertEqual(result['cellMarks']['6']['a'], 'N/A')
            self.assertEqual(sum(len(parts) for parts in result['cellResults'].values()), 28)

    def test_exif_orientation_precedes_manual_rotation(self):
        upright = grid()
        sideways = np.ascontiguousarray(np.rot90(upright))
        photo = Image.fromarray(cv2.cvtColor(sideways, cv2.COLOR_BGR2RGB))
        photo.getexif()[274] = 6  # 90 clockwise display orientation.
        buffer = io.BytesIO()
        photo.save(buffer, format='JPEG', exif=photo.getexif())
        buffer.seek(0)
        with Image.open(buffer) as encoded:
            oriented = orient_image(encoded)
            self.assertEqual(oriented.shape, upright.shape)
            result = process_table(encoded, MarkRecognizer(backend=Backend()),
                                   normalized_corners=detect_corners(oriented))
            self.assertEqual(result['cellMarks']['1']['a'], '15')
            np.testing.assert_array_equal(orient_image(encoded, 90), np.rot90(oriented, -1))

    def test_manual_corners_work_without_automatic_grid_evidence(self):
        image = np.full((850,650,3), 255, np.uint8)
        # Known reference layout, with ink but no borders for the detector.
        cv2.putText(image, '7', (230,240), cv2.FONT_HERSHEY_SIMPLEX, 1, (0,0,0), 2)
        corners = [[50,50],[550,50],[550,790],[50,790]]
        with patch('ocr.cell_extractor._locate_candidates', side_effect=AssertionError('Manual selection must skip localization')):
            cells = extract_cells(image, corners=corners).cells
        self.assertEqual(len(cells), 28)
        self.assertGreater(np.count_nonzero(cells[0].image < 100), 100)

    def test_normalized_corners_survive_large_image_downscaling(self):
        large = cv2.resize(grid(), None, fx=4, fy=4)
        cells = extract_cells(large, corners=pixel_corners(detect_corners(large), large.shape)).cells
        reference = extract_cells(grid()).cells
        for actual, expected in zip(cells, reference):
            np.testing.assert_allclose(np.array(actual.bounds)/4, expected.bounds, atol=3)

    def test_invalid_geometry_and_rotations_are_rejected(self):
        valid = [[.1,.1],[.9,.1],[.9,.9],[.1,.9]]
        invalid = [valid[:3], [[-1,0],[1,0],[1,1],[0,1]],
                   [[0,0],[1,1],[1,0],[0,1]], list(reversed(valid)),
                   [[0,0],[0,0],[1,1],[0,1]], [[float('nan'),0],[1,0],[1,1],[0,1]],
                   [[.1,.1],[.101,.1],[.101,.101],[.1,.101]]]
        for points in invalid:
            with self.assertRaises(ValueError):
                pixel_corners(points, (850,650,3))
        for rotation in (-90, 45, 360, True, '90', 90.0):
            with self.assertRaises(ValueError):
                orient_image(grid(), rotation)
        with self.assertRaises(ValueError):
            process_table(grid(), MarkRecognizer(backend=Backend()),
                          corners=valid, normalized_corners=valid)


class DetectionApiTests(unittest.TestCase):
    def test_detection_fallback_manual_request_and_authentication(self):
        recognizer = MarkRecognizer(backend=Backend())
        server = HTTPServer(('127.0.0.1', 0), make_handler(recognizer, 'test-token'))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def post(path, body, token='test-token'):
            connection = HTTPConnection('127.0.0.1', server.server_port)
            try:
                connection.request('POST', path, json.dumps(body), {'Authorization': f'Bearer {token}'})
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            finally:
                connection.close()

        image = base64.b64encode(SAMPLE.read_bytes()).decode()
        try:
            with patch.object(recognizer, 'predict_mark', side_effect=AssertionError('Detection must not run OCR')):
                status, detection = post('/ocr/detect', {'image_base64': image})
            self.assertEqual(status, 200)
            self.assertTrue(detection['detected'])
            self.assertEqual(len(detection['normalized_corners']), 4)
            status, result = post('/ocr/table', {'image_base64': image, 'table_type': '5-8',
                'rotation': 0, 'normalized_corners': detection['normalized_corners']})
            self.assertEqual(status, 200)
            self.assertEqual(result['questions'], ['5','6','7','8'])
            self.assertEqual(post('/ocr/detect', {'image_base64': image}, 'wrong')[0], 401)
            self.assertEqual(post('/ocr/detect', {'image_base64': image, 'rotation': 45})[0], 422)
            self.assertEqual(post('/ocr/table', {'image_base64': image, 'normalized_corners': [[0,0]]})[0], 422)
            buffer = io.BytesIO()
            Image.new('RGB', (300,300), 'white').save(buffer, format='PNG')
            status, detection = post('/ocr/detect', {'image_base64': base64.b64encode(buffer.getvalue()).decode()})
            self.assertEqual(status, 200)
            self.assertFalse(detection['detected'])
            self.assertIsNone(detection['normalized_corners'])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
