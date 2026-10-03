import tempfile
import unittest
from pathlib import Path
from PIL import Image
from ocr.config import CHAR_TO_INDEX
from ocr.ctc import encode_label
from ocr.dataset import CellDataset, collate_cells, ensure_disjoint, split_dataset


class DatasetTests(unittest.TestCase):
    def test_encoding(self):
        self.assertEqual(encode_label('15'), [CHAR_TO_INDEX['1'], CHAR_TO_INDEX['5']])
        for text in ['', '123', '7.5', '-1', '１２']:
            with self.assertRaises(ValueError):
                encode_label(text)

    def test_loader_collation_and_grouped_split(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = ['image_path,label,group']
            for index in range(6):
                Image.new('L', (20, 20), 255).save(root / f'{index}.png')
                rows.append(f'{index}.png,11,writer{index // 2}')
            path = root / 'labels.csv'
            path.write_text('\n'.join(rows), encoding='utf-8')
            dataset = CellDataset(path)
            first, second = split_dataset(dataset, seed=42)
            ensure_disjoint(first, second)
            self.assertEqual(split_dataset(dataset, seed=42)[0].samples, first.samples)
            images, targets, lengths, labels = collate_cells([dataset[0], dataset[1]])
            self.assertEqual(tuple(images.shape), (2, 1, 32, 96))
            self.assertEqual(targets.tolist(), encode_label('11') * 2)
            self.assertEqual(lengths.tolist(), [2, 2])
            with self.assertRaisesRegex(ValueError, 'overlap'):
                ensure_disjoint(dataset, dataset)

    def test_empty_dataset_error(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'labels.csv'
            path.write_text('image_path,label\n', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'empty'):
                CellDataset(path)
