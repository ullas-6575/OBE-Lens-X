"""Evaluate a trained checkpoint on a separately held-out CSV."""
import argparse
from collections import Counter
import json
from pathlib import Path
import torch
from torch.utils.data import DataLoader
from .config import DEFAULT_CHECKPOINT
from .ctc import decode_prediction
from .dataset import CellDataset, collate_cells
from .metrics import edit_distance, evaluate_loader
from .runtime import load_checkpoint


def summarize_pairs(pairs):
    if not pairs:
        return {'samples': 0, 'exact_sequence_accuracy': None, 'character_error_rate': None}
    return {'samples': len(pairs),
            'exact_sequence_accuracy': sum(label == pred for label, pred in pairs) / len(pairs),
            'character_error_rate': sum(edit_distance(label, pred) for label, pred in pairs) /
                                    sum(len(label) for label, _ in pairs)}


@torch.inference_mode()
def evaluate(manifest, *, checkpoint=DEFAULT_CHECKPOINT, batch_size=32, device='auto'):
    if batch_size < 1:
        raise ValueError('Batch size must be positive')
    model, preprocessing, _ = load_checkpoint(checkpoint, device)
    actual_device = next(model.parameters()).device
    dataset = CellDataset(manifest, preprocessing=preprocessing)
    loader = DataLoader(dataset, batch_size=batch_size, collate_fn=collate_cells)
    report = evaluate_loader(model, loader, actual_device)
    predictions = []
    for images, _, _, _ in loader:
        paths = model(images.to(actual_device)).argmax(2).transpose(0, 1).cpu()
        predictions.extend(decode_prediction(path) for path in paths)
    pairs = [(sample.label, prediction) for sample, prediction in zip(dataset.samples, predictions)]
    report['device'] = str(actual_device)
    report['by_label_type'] = {
        'one_digit': summarize_pairs([(label, pred) for label, pred in pairs if len(label) == 1]),
        'two_digit': summarize_pairs([(label, pred) for label, pred in pairs if len(label) == 2]),
        'repeated_digit': summarize_pairs([(label, pred) for label, pred in pairs
                                          if len(label) == 2 and label[0] == label[1]]),
    }
    confusion = Counter((label, pred) for label, pred in pairs if label != pred)
    report['confusions'] = [{'expected': label, 'predicted': pred, 'count': count}
                            for (label, pred), count in confusion.most_common()]
    report['predictions'] = [{'image_path': str(sample.image_path), 'expected': sample.label,
                              'predicted': pred} for sample, pred in zip(dataset.samples, predictions)]
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', required=True, help='Held-out CSV manifest')
    parser.add_argument('--checkpoint', default=str(DEFAULT_CHECKPOINT))
    parser.add_argument('--batch-size', type=int, default=32)
    parser.add_argument('--device', choices=['auto', 'cpu', 'cuda'], default='auto')
    parser.add_argument('--output', help='Optional JSON report path')
    args = parser.parse_args()
    report = evaluate(args.test, checkpoint=args.checkpoint, batch_size=args.batch_size, device=args.device)
    serialized = json.dumps(report, indent=2)
    if args.output:
        path = Path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(serialized + '\n', encoding='utf-8')
    print(serialized)


if __name__ == '__main__':
    main()
