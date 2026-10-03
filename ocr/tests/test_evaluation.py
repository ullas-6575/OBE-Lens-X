import tempfile
import unittest
from pathlib import Path
from PIL import Image
import torch
from ocr.config import PreprocessingConfig
from ocr.evaluate import evaluate, summarize_pairs
from ocr.metrics import edit_distance
from ocr.model import MarksCRNN
from ocr.runtime import save_checkpoint


class EvaluationTests(unittest.TestCase):
    def test_known_metrics(self):
        self.assertEqual(edit_distance('15', '16'), 1)
        self.assertEqual(edit_distance('11', ''), 2)
        report = summarize_pairs([('15', '16'), ('0', '0')])
        self.assertEqual(report['exact_sequence_accuracy'], 0.5)
        self.assertAlmostEqual(report['character_error_rate'], 1 / 3)
        self.assertIsNone(summarize_pairs([])['character_error_rate'])

    def test_standalone_evaluation(self):
        torch.set_num_threads(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = MarksCRNN()
            with torch.no_grad():
                model.classifier.weight.zero_()
                model.classifier.bias.zero_()
                model.classifier.bias[0] = 20
            save_checkpoint(root / 'fixture.pth', model, PreprocessingConfig())
            rows = ['image_path,label']
            for i, label in enumerate(['0', '15', '11']):
                Image.new('L', (30, 20), 255).save(root / f'{i}.png')
                rows.append(f'{i}.png,{label}')
            (root / 'test.csv').write_text('\n'.join(rows), encoding='utf-8')
            report = evaluate(root / 'test.csv', checkpoint=root / 'fixture.pth')
            self.assertEqual(report['samples'], 3)
            self.assertEqual(report['exact_sequence_accuracy'], 0)
            self.assertEqual(report['character_error_rate'], 1)
            self.assertEqual(report['by_label_type']['repeated_digit']['samples'], 1)
            self.assertEqual(len(report['predictions']), 3)
