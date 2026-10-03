import unittest
import numpy as np
import torch
from PIL import Image, ImageDraw
from ocr.config import PreprocessingConfig
from ocr.preprocessing import preprocess, prepare_image, load_image


class PreprocessingTests(unittest.TestCase):
    def test_aspect_ratio_and_normalization(self):
        image = Image.new('L', (100, 20), 0)
        output = prepare_image(image, PreprocessingConfig(trim_whitespace=False))
        box = output.point(lambda x: 255 if x < 128 else 0).getbbox()
        self.assertAlmostEqual((box[2] - box[0]) / (box[3] - box[1]), 5, delta=0.3)
        tensor = preprocess(image)
        self.assertEqual(tuple(tensor.shape), (1, 32, 96))
        self.assertGreaterEqual(tensor.min().item(), -1)
        self.assertLessEqual(tensor.max().item(), 1)

    def test_trim_and_blank(self):
        image = Image.new('L', (200, 100), 255)
        ImageDraw.Draw(image).rectangle((90, 45, 110, 55), fill=0)
        trimmed = np.array(prepare_image(image))
        untrimmed = np.array(prepare_image(image, PreprocessingConfig(trim_whitespace=False)))
        self.assertGreater((trimmed < 128).sum(), (untrimmed < 128).sum())
        self.assertTrue(torch.all(preprocess(Image.new('L', (20, 20), 255)) == -1))
        self.assertTrue(torch.all(preprocess(Image.new('RGBA', (20, 20), (0, 0, 0, 0))) == -1))

    def test_array_color_and_options(self):
        bgr = np.zeros((10, 20, 3), dtype=np.uint8)
        bgr[:, :, 2] = 255
        self.assertEqual(load_image(bgr).getpixel((0, 0)), (255, 0, 0))
        cfg = PreprocessingConfig(threshold=128, median_filter_size=3)
        self.assertEqual(tuple(preprocess(bgr, cfg).shape), (1, 32, 96))
        for image in [np.zeros((0, 10), dtype=np.uint8), np.zeros((10, 10), dtype=float)]:
            with self.assertRaises(ValueError):
                preprocess(image)
