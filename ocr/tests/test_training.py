import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image, ImageDraw
import torch
from ocr.config import TrainingConfig, PreprocessingConfig
from ocr.train import train
from ocr.runtime import load_checkpoint, select_device


class TrainingTests(unittest.TestCase):
    def test_cpu_fallback(self):
        with patch('torch.cuda.is_available', return_value=False):
            self.assertEqual(select_device('auto').type, 'cpu')
            self.assertEqual(select_device('cuda').type, 'cpu')
        with patch('torch.cuda.is_available', return_value=True):
            self.assertEqual(select_device('auto').type, 'cuda')

    def test_training_and_reproducibility(self):
        torch.set_num_threads(1)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = ['image_path,label,group']
            for index, label in enumerate(['0', '11', '15', '20']):
                image = Image.new('L', (60, 30), 255)
                ImageDraw.Draw(image).text((10, 10), label, fill=0)
                image.save(root / f'{index}.png')
                rows.append(f'{index}.png,{label},writer{index}')
            manifest = root / 'labels.csv'
            manifest.write_text('\n'.join(rows), encoding='utf-8')
            cfg = TrainingConfig(epochs=1, batch_size=2, seed=42)
            prep = PreprocessingConfig(threshold=128)
            with contextlib.redirect_stdout(io.StringIO()):
                first = train(manifest, output=root / 'first.pth', config=cfg, preprocessing=prep)
                second = train(manifest, output=root / 'second.pth', config=cfg, preprocessing=prep)
            self.assertEqual(first, second)
            for field in ['training_loss', 'validation_loss', 'exact_sequence_accuracy', 'character_error_rate']:
                self.assertIn(field, first[0])
            model, restored, payload = load_checkpoint(root / 'first.pth')
            self.assertEqual(restored, prep)
            self.assertEqual(payload['epoch'], 1)
            self.assertIn('optimizer_state', payload)
            self.assertTrue((root / 'first_checkpoints/epoch_001.pth').is_file())
            split = json.loads((root / 'first_checkpoints/split.json').read_text())
            self.assertTrue(split['train'] and split['val'])
