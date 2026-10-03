import itertools
import math
import unittest
import torch
from ocr.ctc import encode_label, decode_prediction, ctc_loss, sequence_log_probability
from ocr.model import MarksCRNN


class CtcTests(unittest.TestCase):
    def test_examples_and_repeats(self):
        for text in ['0', '1', '5', '8', '9', '10', '12', '15', '20', '25', '11', '00']:
            path = [0]
            for token in encode_label(text):
                path.extend([token, token, 0])
            self.assertEqual(decode_prediction(path), text)
            scores = torch.full((len(path), 11), -10.)
            scores[range(len(path)), path] = 10.
            self.assertEqual(decode_prediction(scores), text)
        self.assertEqual(decode_prediction([2, 2, 0, 2]), '11')
        self.assertEqual(decode_prediction([2, 2]), '1')

    def test_loss_and_backward(self):
        torch.set_num_threads(1)
        model = MarksCRNN()
        loss = ctc_loss(model(torch.zeros(2, 1, 32, 96)),
                        torch.tensor(encode_label('11') + encode_label('0')),
                        torch.tensor([2, 1]))
        self.assertTrue(torch.isfinite(loss))
        loss.backward()
        with self.assertRaises(ValueError):
            ctc_loss(model(torch.zeros(1, 1, 32, 96)), torch.tensor([0]), torch.tensor([1]))

    def test_probability_matches_all_alignments(self):
        probs = [[0.4, 0.35, 0.25] + [0.] * 8] * 4
        logs = [[math.log(p) if p else -math.inf for p in row] for row in probs]
        for text in ['0', '1', '00', '01']:
            expected = sum(math.prod(probs[t][v] for t, v in enumerate(path))
                           for path in itertools.product(range(3), repeat=4)
                           if decode_prediction(list(path)) == text)
            self.assertAlmostEqual(math.exp(sequence_log_probability(logs, text)), expected)
