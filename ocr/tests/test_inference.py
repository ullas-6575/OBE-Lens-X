import tempfile
import unittest
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
import torch
from ocr.config import InferenceConfig, PreprocessingConfig
from ocr.inference import MarkRecognizer
from ocr.model import MarksCRNN
from ocr.runtime import save_checkpoint
from ocr import predict_mark


class InferenceTests(unittest.TestCase):
    def test_path_and_array_have_same_result(self):
        torch.set_num_threads(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = MarksCRNN()
            with torch.no_grad():
                model.classifier.weight.zero_()
                model.classifier.bias.zero_()
                model.classifier.bias[2] = 20  # Constant token for '1'.
            save_checkpoint(root / 'fixture.pth', model, PreprocessingConfig())
            image = Image.new('RGB', (60, 30), 'white')
            ImageDraw.Draw(image).text((10, 10), '1', fill='black')
            image.save(root / 'cell.png')
            recognizer = MarkRecognizer(root / 'fixture.pth', config=InferenceConfig(device='cpu'))
            path_result = recognizer.predict_sequence(root / 'cell.png')
            array_result = recognizer.predict_sequence(np.array(image)[:, :, ::-1])
            self.assertEqual(path_result, array_result)
            self.assertEqual(path_result['text'], '1')
            self.assertGreater(path_result['confidence'], 0.99)
            final = predict_mark(root / 'cell.png', max_mark=10,
                                 checkpoint=root / 'fixture.pth')
            self.assertEqual(final['value'], 1)
            self.assertTrue(final['valid'])
            self.assertFalse(final['needs_review'])
            invalid = recognizer.predict_mark(np.array(image), max_mark=0)
            self.assertIsNone(invalid['value'])
            self.assertTrue(invalid['needs_review'])

    def test_missing_checkpoint_is_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(FileNotFoundError, 'No trained checkpoint'):
                MarkRecognizer(Path(directory) / 'missing.pth')
