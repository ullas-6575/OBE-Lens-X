import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock
from PIL import Image
from ocr.corrections import save_correction, export_corrections
from ocr.dataset import CellDataset
from ocr.table_processing import ExtractedCell, process_cells
from ocr.validation import apply_confidence


class IntegrationTests(unittest.TestCase):
    def test_cells_keep_review_and_question_limits(self):
        recognizer = Mock()
        recognizer.predict_mark.side_effect = [apply_confidence('18', 0.62, max_mark=20),
                                              apply_confidence('15', 0.96, max_mark=10)]
        cells = [ExtractedCell('1', 'a', 'cell_a.png', max_mark=20, bounds=(0, 0, 20, 20)),
                 ExtractedCell('2', 'b', 'cell_b.png', max_mark=10)]
        result = process_cells(cells, recognizer, image_path='sheet.png')
        self.assertEqual(result['cellMarks']['1']['a'], '18')
        self.assertEqual(result['cellMarks']['2']['b'], '')
        self.assertTrue(result['cellResults']['1']['a']['needs_review'])
        self.assertIsNone(result['cellResults']['2']['b']['value'])
        self.assertEqual(result['cellResults']['1']['a']['bounds'], (0, 0, 20, 20))
        self.assertTrue(result['needsReview'])
        self.assertFalse(result['isVerified'])
        self.assertEqual(result['cellResults']['4']['g']['reason'], 'cell_not_supplied')
        recognizer.predict_mark.assert_any_call('cell_b.png', max_mark=10)

    def test_invalid_cell_mapping(self):
        with self.assertRaises(ValueError):
            process_cells([ExtractedCell('5', 'a', 'image.png')], Mock(), table_type='1-4')
        with self.assertRaises(ValueError):
            process_cells([], Mock(), table_type='unknown')

    def test_correction_roundtrip_to_dataset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = Image.new('L', (40, 20), 255)
            record_path = save_correction(image, predicted='18', confidence=0.62, corrected='16',
                                          max_mark=20, group='writer1', output_dir=root,
                                          metadata={'question': '1', 'part': 'a'})
            record = json.loads(record_path.read_text())
            self.assertEqual(record['predicted'], '18')
            self.assertEqual(record['corrected'], '16')
            with Image.open(root / record['image_path']) as restored:
                self.assertEqual(restored.size, image.size)
            manifest = export_corrections([record_path], root / 'corrections.csv')
            dataset = CellDataset(manifest)
            self.assertEqual(dataset.samples[0].label, '16')
            self.assertEqual(dataset.samples[0].group, 'writer1')
            with self.assertRaises(ValueError):
                save_correction(image, predicted='18', confidence=0.62, corrected='21',
                                max_mark=20, output_dir=root)
