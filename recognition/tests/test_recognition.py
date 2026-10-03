import itertools
import math
import tempfile
import unittest
from pathlib import Path

from cell_ocr.decoding import encode, greedy_decode, sequence_log_probability, validate


class DecodingTests(unittest.TestCase):
    def test_examples_and_repeated_digits(self):
        for text in ['0', '1', '5', '8', '9', '10', '12', '15', '20', '25', '11', '00']:
            path = [0]
            for token in encode(text):
                path.extend([token, token, 0])
            self.assertEqual(greedy_decode(path), text)

    def test_policy_does_not_truncate_invalid_predictions(self):
        for text in ['', '123', '-1', '2.5', 'a', '１２']:
            self.assertFalse(validate(text, 0.5).valid)
            with self.assertRaises(ValueError):
                encode(text)
        self.assertFalse(validate('25', 0.9, 20).valid)
        self.assertEqual(validate('0', 0.9).value, 0)
        self.assertTrue(validate('20', 0.9).requires_review)

    def test_forward_probability_matches_exhaustive_alignments(self):
        probabilities = [[0.4, 0.35, 0.25] + [0.0] * 8] * 4
        logs = [[math.log(p) if p else -math.inf for p in row] for row in probabilities]
        for text in ['0', '1', '00', '01']:
            expected = sum(math.prod(probabilities[t][v] for t, v in enumerate(path))
                           for path in itertools.product(range(3), repeat=4)
                           if greedy_decode(list(path)) == text)
            self.assertAlmostEqual(math.exp(sequence_log_probability(logs, text)), expected)


class ModelTests(unittest.TestCase):
    def test_training_manifest_to_checkpoint(self):
        import argparse
        import contextlib
        import io
        import torch
        from PIL import Image
        from cell_ocr.cli import train
        from cell_ocr.inference import CellRecognizer
        torch.set_num_threads(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['train', 'validation']:
                Image.new('L', (40, 20), 255).save(root / f'{name}.png')
                (root / f'{name}.csv').write_text(
                    f'image_path,label\n{name}.png,11\n', encoding='utf-8')
            args = argparse.Namespace(train=root / 'train.csv',
                                      validation=root / 'validation.csv',
                                      output=root / 'best.pt', epochs=1,
                                      batch_size=1, seed=42)
            with contextlib.redirect_stdout(io.StringIO()):
                train(args)
            self.assertTrue((root / 'best.pt').is_file())
            CellRecognizer(root / 'best.pt')
            args.validation = args.train
            with self.assertRaisesRegex(ValueError, 'overlap'):
                train(args)

    def test_preprocessing_and_ctc_backward(self):
        import torch
        from PIL import Image
        from cell_ocr.model import CRNN
        from cell_ocr.preprocessing import preprocess
        torch.set_num_threads(1)
        tensor = preprocess(Image.new('RGBA', (200, 40), (0, 0, 0, 0)))
        self.assertEqual(tuple(tensor.shape), (1, 32, 96))
        self.assertTrue(torch.all(tensor == -1))
        model = CRNN()
        logits = model(tensor.unsqueeze(0))
        self.assertEqual(tuple(logits.shape), (24, 1, 11))
        loss = torch.nn.CTCLoss()(logits.log_softmax(2), torch.tensor(encode('11')),
                                 torch.tensor([24]), torch.tensor([2]))
        loss.backward()
        self.assertTrue(torch.isfinite(loss))

    def test_checkpoint_roundtrip(self):
        import torch
        from PIL import Image
        from cell_ocr.model import CRNN
        from cell_ocr.inference import CellRecognizer, FORMAT_VERSION
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'model.pt'
            model = CRNN()
            # Force a deterministic blank output; never pretend random weights are trained.
            with torch.no_grad():
                model.classifier.weight.zero_()
                model.classifier.bias.zero_()
                model.classifier.bias[0] = 20
            torch.save({'format_version': FORMAT_VERSION, 'model_state': model.state_dict()}, path)
            result = CellRecognizer(path).recognize(Image.new('L', (50, 30), 255))
            self.assertEqual(result.text, '')
            self.assertFalse(result.valid)
            self.assertEqual(result.confidence, 0)


if __name__ == '__main__':
    unittest.main()
