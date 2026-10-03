import unittest
import torch
from ocr.model import MarksCRNN
from ocr.config import ModelConfig


class ModelTests(unittest.TestCase):
    def test_lightweight_shape_and_gradients(self):
        torch.set_num_threads(1)
        model = MarksCRNN()
        self.assertLess(sum(p.numel() for p in model.parameters()), 300_000)
        logits = model(torch.zeros(2, 1, 32, 96))
        self.assertEqual(tuple(logits.shape), (24, 2, 11))
        logits.square().mean().backward()
        self.assertTrue(all(p.grad is not None for p in model.parameters()))
        other = MarksCRNN(ModelConfig(hidden_size=32))
        self.assertEqual(tuple(other(torch.zeros(1, 1, 48, 128)).shape), (32, 1, 11))
