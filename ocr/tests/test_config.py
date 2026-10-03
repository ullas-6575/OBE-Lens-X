import unittest
from ocr.config import (BLANK_INDEX, CHAR_TO_INDEX, INDEX_TO_CHAR,
                        NUM_CLASSES, PreprocessingConfig, TrainingConfig,
                        InferenceConfig)


class ConfigTests(unittest.TestCase):
    def test_vocabulary(self):
        self.assertEqual(NUM_CLASSES, 11)
        self.assertNotIn(BLANK_INDEX, INDEX_TO_CHAR)
        for char in '0123456789':
            self.assertEqual(INDEX_TO_CHAR[CHAR_TO_INDEX[char]], char)

    def test_invalid_settings(self):
        for kwargs in [{'width': 8}, {'padding': 16}, {'threshold': 300},
                       {'median_filter_size': 2}, {'array_color_order': 'XYZ'}]:
            with self.assertRaises(ValueError):
                PreprocessingConfig(**kwargs)
        with self.assertRaises(ValueError):
            TrainingConfig(learning_rate=0)
        with self.assertRaises(ValueError):
            InferenceConfig(confidence_threshold=float('nan'))
