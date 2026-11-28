import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from ocr import MarkRecognizer
from ocr.config import RecognitionConfig
from ocr.empty_cell import is_empty_cell
from ocr.preprocessing import prepare_cell
from ocr.table_processor import ExtractedCell, process_cells


class Backend:
    def __init__(self, text='15', score=.9):
        self.text, self.score, self.calls = text, score, 0

    def predict(self, *, input, batch_size):
        self.calls += 1
        assert input.dtype == np.uint8 and input.shape[2] == 3
        return [{'rec_text': self.text, 'rec_score': self.score}]


class RecognitionTests(unittest.TestCase):
    def test_missing_local_model_never_initializes_paddle(self):
        factory = Mock()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'inference.onnx').touch()
            with patch.dict('sys.modules', {'paddleocr': SimpleNamespace(TextRecognition=factory)}):
                for model_dir in (None, str(root / 'missing'), str(root)):
                    with self.subTest(model_dir=model_dir):
                        recognizer = MarkRecognizer(RecognitionConfig(model_dir=model_dir))
                        with self.assertRaises((ValueError, FileNotFoundError)):
                            recognizer.predict_mark(Image.new('RGB', (20, 20), 'black'))
        factory.assert_not_called()

    def test_supplied_model_path_is_used_and_recognizer_is_reused(self):
        backend = Backend()
        factory = Mock(return_value=backend)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            for name in ('inference.onnx', 'inference.yml'):
                (root / name).touch()
            with patch.dict('sys.modules', {'paddleocr': SimpleNamespace(TextRecognition=factory)}):
                recognizer = MarkRecognizer(RecognitionConfig(model_dir=str(root)))
                for _ in range(2):
                    self.assertEqual(recognizer.predict_mark(Image.new('RGB', (20, 20), 'black'))['value'], 15)
            factory.assert_called_once_with(model_name='en_PP-OCRv5_mobile_rec',
                                            model_dir=str(root), device='cpu',
                                            engine='onnxruntime',
                                            engine_config={'intra_op_num_threads': 2})
            self.assertEqual(backend.calls, 2)

    def test_default_uses_obelens_in_original_model_directory(self):
        root = Path(__file__).resolve().parents[1] / 'models/recognition'
        factory = Mock(return_value=Backend())
        with patch.dict('sys.modules', {'paddleocr': SimpleNamespace(TextRecognition=factory)}):
            recognizer = MarkRecognizer()
            self.assertEqual(recognizer.predict_mark(Image.new('RGB', (20, 20), 'black'))['value'], 15)
        self.assertEqual(factory.call_args.kwargs['model_dir'], str(root))
        self.assertEqual(factory.call_args.kwargs['engine'], 'onnxruntime')
        self.assertEqual(recognizer.config.model_name, 'obelens')

    def test_raw_predictions_validation_and_review(self):
        for text, score, valid, review in [('15', .9, True, False), ('15', .3, True, True),
                                         ('I5', .99, False, True), ('21', .99, False, True),
                                         ('100', .99, False, True), (' 5 ', .99, True, False),
                                         ('\u09e7\u09e8', .99, False, True),
                                         ('\u0661\u0662', .99, False, True),
                                         ('\uff11\uff12', .99, False, True)]:
            result = MarkRecognizer(backend=Backend(text, score)).predict_mark(Image.new('RGB', (20, 20), 'black'), 20)
            self.assertEqual((result['text'], result['valid'], result['needs_review']), (text, valid, review))

    def test_blank_is_not_zero(self):
        backend = Backend('0')
        recognizer = MarkRecognizer(backend=backend)
        result = recognizer.predict_mark(Image.new('RGB', (20, 20), 'white'))
        self.assertIsNone(result['value'])
        self.assertEqual(result['reason'], 'empty_cell')
        self.assertEqual(backend.calls, 0)
        self.assertEqual(recognizer.predict_mark(Image.new('RGB', (20, 20), 'black'))['value'], 0)

    def test_paper_noise_is_blank_but_faint_strokes_reach_ocr(self):
        rng = np.random.default_rng(42)
        paper = np.tile(np.linspace(180, 200, 80), (50, 1)) + rng.normal(0, 1, (50, 80))
        paper = np.clip(paper, 0, 255).astype(np.uint8)
        self.assertTrue(is_empty_cell(prepare_cell(paper)))
        faint = Image.new('RGB', (80, 50), (210, 210, 210))
        ImageDraw.Draw(faint).line([(20, 10), (40, 10), (25, 40)], fill=(204, 204, 204), width=2)
        backend = Backend('7', .2)
        result = MarkRecognizer(backend=backend).predict_mark(faint)
        self.assertEqual(backend.calls, 1)
        self.assertEqual(result['text'], '7')
        self.assertTrue(result['needs_review'])

    def test_table_allows_only_numeric_marks_and_flags_only_uncertain_cells(self):
        image = Image.new('RGB', (20, 20), 'black')
        for text, expected in [('15', '15'), ('o7', 'N/A'), ('21', '21'),
                               ('/', 'N/A'), ('-', 'N/A'), ('?', 'N/A'),
                               ('100', 'N/A'), ('07', '07'), ('0', '0'),
                               ('1.5', 'N/A'), (' 5 ', '5')]:
            payload = process_cells([ExtractedCell('1', 'a', image, max_mark=20)],
                                    MarkRecognizer(backend=Backend(text, .1)))
            self.assertEqual(payload['cellMarks']['1']['a'], expected)
            self.assertEqual(payload['cellResults']['1']['a']['text'], text)
            self.assertTrue(payload['cellResults']['1']['a']['needs_review'])
        certain = process_cells([ExtractedCell('1', 'a', image)], MarkRecognizer(backend=Backend('07', .99)))
        self.assertFalse(certain['cellResults']['1']['a']['needs_review'])
        blank = process_cells([ExtractedCell('1', 'a', Image.new('RGB', (20,20), 'white'))],
                              MarkRecognizer(backend=Backend()))
        self.assertEqual(blank['cellMarks']['1']['a'], 'N/A')
        self.assertFalse(blank['cellResults']['1']['a']['needs_review'])
        # Handwriting with no recognized text is unknown, not a confidently blank cell.
        unknown = process_cells([ExtractedCell('1', 'a', image)], MarkRecognizer(backend=Backend('')))
        self.assertEqual(unknown['cellMarks']['1']['a'], 'N/A')
        self.assertTrue(unknown['cellResults']['1']['a']['needs_review'])

    def test_color_transparency(self):
        self.assertEqual(prepare_cell(Image.new('RGB', (2, 2), 'red'))[0, 0].tolist(), [0, 0, 255])
        self.assertTrue(np.all(prepare_cell(Image.new('RGBA', (2, 2), (0, 0, 0, 0))) == 255))

    def test_complete_empty_table_has_no_warnings_and_skips_recognition(self):
        backend = Backend('o7', .1)
        cells = [ExtractedCell(q, p, Image.new('RGB', (20,20), 'white'))
                 for q in ('1','2','3','4') for p in 'abcdefg']
        payload = process_cells(cells, MarkRecognizer(backend=backend))
        self.assertFalse(payload['needsReview'])
        self.assertEqual(backend.calls, 0)
        self.assertTrue(all(mark == 'N/A' for column in payload['cellMarks'].values() for mark in column.values()))

    def test_malformed_backend_results_fail_explicitly(self):
        class WrappedBackend:
            def predict(self, **kwargs):
                return [{'res': {'rec_text': '10', 'rec_score': .95}}]
        image = Image.new('RGB', (20, 20), 'black')
        self.assertEqual(MarkRecognizer(backend=WrappedBackend()).predict_mark(image)['value'], 10)
        with self.assertRaises(ValueError):
            MarkRecognizer(backend=Backend(score=float('nan'))).predict_mark(image)
        with self.assertRaises(ValueError):
            MarkRecognizer(backend=Backend()).predict_mark(image, max_mark=-1)

    def test_missing_table_cells_remain_unresolved(self):
        payload = process_cells([ExtractedCell('1', 'a', Image.new('RGB', (20, 20), 'black'))],
                                MarkRecognizer(backend=Backend(score=.3)))
        self.assertEqual(payload['cellMarks']['1']['a'], '15')
        self.assertEqual(payload['cellMarks']['1']['b'], 'N/A')
        self.assertTrue(payload['needsReview'])
        self.assertFalse(payload['isVerified'])


if __name__ == '__main__':
    unittest.main()
