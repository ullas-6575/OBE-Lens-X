"""Exercise the deployed model, including its English-digit output restriction."""
from pathlib import Path
import unittest

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont

from ocr import MarkRecognizer
from ocr.full_table import process_table


ROOT = Path(__file__).resolve().parents[2]


class ObelensModelTests(unittest.TestCase):
    def test_captured_q5_q8_photo_reads_marks_in_the_correct_cells(self):
        expected = {str(q): {part: 'N/A' for part in 'abcdefg'} for q in range(5,9)}
        expected['5'].update(a='13',b='07',c='08')
        expected['7'].update(a='05',c='07',d='06')
        expected['8'].update(a='09',b='11',c='06')
        recognizer = MarkRecognizer()
        for filename in ('answer_table_q5_q8.jpg','answer_table_perspective.jpg'):
            with self.subTest(photo=filename):
                payload = process_table(ROOT/'obelens-ocr/tests/fixtures'/filename,
                                        recognizer,table_type='5-8')
                self.assertEqual(payload['cellMarks'],expected)

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
