"""Exercise the deployed model, including its English-digit output restriction."""
from pathlib import Path
import unittest

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont

from ocr import MarkRecognizer


ROOT = Path(__file__).resolve().parents[2]


class ObelensModelTests(unittest.TestCase):
    def test_android_and_service_use_identical_model(self):
        self.assertEqual(
            (ROOT / 'assets/ocr_model/obelens.onnx').read_bytes(),
            (ROOT / 'obelens-ocr/models/recognition/inference.onnx').read_bytes(),
        )

    def test_only_english_digit_and_blank_classes_can_win(self):
        options = ort.SessionOptions()
        options.intra_op_num_threads = 2
        session = ort.InferenceSession(
            str(ROOT / 'assets/ocr_model/obelens.onnx'), options,
            providers=['CPUExecutionProvider'],
        )
        characters = (ROOT / 'assets/ocr_model/ppocrv5_en_dict.txt').read_text().splitlines() + [' ']
        allowed = [0] + [i + 1 for i, char in enumerate(characters)
                         if len(char) == 1 and char in '0123456789']
        forbidden = [i for i in range(len(characters) + 1) if i not in allowed]
        probes = [np.ones((1, 3, 48, 320), dtype=np.float32),
                  np.random.default_rng(42).uniform(-1, 1, (1, 3, 48, 320)).astype(np.float32)]
        for probe in probes:
            scores = session.run(None, {'x': probe})[0]
            self.assertEqual(scores.shape[-1], len(characters) + 1)
            self.assertTrue(np.isfinite(scores).all())
            self.assertTrue((scores[..., forbidden] == 0).all())
            self.assertTrue(np.isin(scores.argmax(-1), allowed).all())
            self.assertTrue((scores[..., allowed] > 0).any())

    def test_python_decoder_returns_only_english_digits(self):
        recognizer = MarkRecognizer()
        font = ImageFont.truetype(str(ROOT / 'assets/fonts/FreeSans.ttf'), 32)
        for text in ('07', 'AZ', '\u09e7\u09e8', '\u0661\u0662', '?@'):
            with self.subTest(text=text):
                image = Image.new('RGB', (160, 48), 'white')
                ImageDraw.Draw(image).text((8, 0), text, font=font, fill='black')
                prediction = recognizer.predict_mark(image)
                self.assertRegex(prediction['text'], r'^[0-9]*$')


if __name__ == '__main__':
    unittest.main()
