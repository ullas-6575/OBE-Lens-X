import tempfile
import unittest
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from ocr import MarkRecognizer
from ocr.empty_cell import is_empty_cell
from ocr.preprocessing import prepare_cell
from ocr.table_processor import ExtractedCell, process_cells
from scripts.test_dataset import evaluate


class Backend:
    def __init__(self, text='15', score=.9):
        self.text, self.score, self.calls = text, score, 0

    def predict(self, *, input, batch_size):
        self.calls += 1
        assert input.dtype == np.uint8 and input.shape[2] == 3
        return [{'rec_text': self.text, 'rec_score': self.score}]


class BaselineTests(unittest.TestCase):
    def test_raw_predictions_validation_and_review(self):
        for text, score, valid, review in [('15', .9, True, False), ('15', .3, True, True),
                                         ('I5', .99, False, True), ('21', .99, False, True),
                                         ('100', .99, False, True), (' 5 ', .99, False, True)]:
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

    def test_table_shows_all_predictions_and_explicit_na_for_blanks(self):
        image = Image.new('RGB', (20, 20), 'black')
        for text in ['15', 'o7', '21']:
            payload = process_cells([ExtractedCell('1', 'a', image, max_mark=20)],
                                    MarkRecognizer(backend=Backend(text, .1)))
            self.assertEqual(payload['cellMarks']['1']['a'], text)
        blank = process_cells([ExtractedCell('1', 'a', Image.new('RGB', (20,20), 'white'))],
                              MarkRecognizer(backend=Backend()))
        self.assertEqual(blank['cellMarks']['1']['a'], 'N/A')
        self.assertFalse(blank['cellResults']['1']['a']['needs_review'])
        # Handwriting with no recognized text is unknown, not a confidently blank cell.
        unknown = process_cells([ExtractedCell('1', 'a', image)], MarkRecognizer(backend=Backend('')))
        self.assertEqual(unknown['cellMarks']['1']['a'], '?')

    def test_color_transparency(self):
        self.assertEqual(prepare_cell(Image.new('RGB', (2, 2), 'red'))[0, 0].tolist(), [0, 0, 255])
        self.assertTrue(np.all(prepare_cell(Image.new('RGBA', (2, 2), (0, 0, 0, 0))) == 255))

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
        self.assertEqual(payload['cellMarks']['1']['b'], '')
        self.assertTrue(payload['needsReview'])
        self.assertFalse(payload['isVerified'])

    def test_dataset_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            Image.new('RGB', (20, 20), 'black').save(root / 'ink.png')
            Image.new('RGB', (20, 20), 'white').save(root / 'blank.png')
            (root / 'labels.csv').write_text('image_path,label\nink.png,15\nblank.png,\n')
            report = evaluate(root / 'labels.csv', MarkRecognizer(backend=Backend()))
            self.assertEqual(report['exact_accuracy'], 1)
            self.assertEqual(report['review_rate'], 0)


if __name__ == '__main__':
    unittest.main()
