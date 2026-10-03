import unittest
from unittest.mock import patch
from ocr.config import InferenceConfig
from ocr.inference import MarkRecognizer
from ocr.validation import validate_mark, apply_confidence


class ValidationTests(unittest.TestCase):
    def test_requested_examples(self):
        for text, maximum, valid in [('8', 10, True), ('10', 10, True),
                                     ('15', 10, False), ('123', 20, False), ('7.5', 10, False)]:
            result = validate_mark(text, maximum)
            self.assertEqual(result['valid'], valid)
            self.assertEqual(result['value'], int(text) if valid else None)
        self.assertTrue(validate_mark('99')['valid'])
        self.assertEqual(validate_mark('00')['value'], 0)
        for text in ['', '-1', ' 8', '１２', 'NaN', 'abc']:
            self.assertFalse(validate_mark(text)['valid'])
        for maximum in [-1, 2.5, True]:
            with self.assertRaises(ValueError):
                validate_mark('8', maximum)

    def test_uncertain_values_are_preserved(self):
        result = apply_confidence('18', 0.62, confidence_threshold=0.8)
        self.assertEqual(result['text'], '18')
        self.assertEqual(result['value'], 18)
        self.assertTrue(result['needs_review'])
        self.assertFalse(apply_confidence('15', 0.96, max_mark=20)['needs_review'])
        self.assertTrue(apply_confidence('15', 0.96, max_mark=10)['needs_review'])
        self.assertTrue(apply_confidence('', 0, confidence_threshold=0)['needs_review'])

    def test_inference_applies_question_policy_and_threshold(self):
        recognizer = MarkRecognizer.__new__(MarkRecognizer)
        recognizer.config = InferenceConfig(confidence_threshold=0.7)
        with patch.object(recognizer, 'predict_sequence', return_value={'text': '15', 'confidence': 0.75}):
            self.assertFalse(recognizer.predict_mark(None, max_mark=20)['needs_review'])
            self.assertFalse(recognizer.predict_mark(None, max_mark=10)['valid'])
            recognizer.config = InferenceConfig(confidence_threshold=0.8)
            self.assertTrue(recognizer.predict_mark(None, max_mark=20)['needs_review'])
