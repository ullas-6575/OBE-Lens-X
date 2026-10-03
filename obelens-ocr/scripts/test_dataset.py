"""Evaluate pretrained recognition on image_path,label CSV cropped cells."""
import argparse
import csv
import json
from pathlib import Path
from time import perf_counter
from ocr import MarkRecognizer
from ocr.config import RecognitionConfig
from ocr.validation import validate_mark


def evaluate(manifest, recognizer, max_mark=None):
    manifest = Path(manifest)
    with manifest.open(newline='', encoding='utf-8') as stream:
        reader = csv.DictReader(stream)
        if not {'image_path', 'label'} <= set(reader.fieldnames or []):
            raise ValueError('CSV requires image_path,label columns')
        samples = list(reader)
    if not samples:
        raise ValueError('Dataset is empty')
    for row in samples:
        if row['label'] != '' and not validate_mark(row['label'], max_mark)['valid']:
            raise ValueError(f"Invalid reference: {row['label']!r}")
        if not row['image_path'] or not (manifest.parent / row['image_path']).is_file():
            raise ValueError(f"Missing cell: {row['image_path']!r}")
    predictions = []
    for row in samples:
        start = perf_counter()
        result = recognizer.predict_mark(manifest.parent / row['image_path'], max_mark=max_mark)
        correct = result['text'] == row['label'] and (result['valid'] or row['label'] == '')
        predictions.append({**row, **result, 'correct': correct,
                            'elapsed_ms': (perf_counter() - start) * 1000})
    accepted = [p for p in predictions if not p['needs_review']]
    groups = {}
    for name, length in [('blank', 0), ('single_digit', 1), ('two_digits', 2)]:
        subset = [p for p in predictions if len(p['label']) == length]
        groups[name] = {'count': len(subset), 'exact_accuracy':
                        sum(p['correct'] for p in subset) / len(subset) if subset else None}
    confusions = {}
    for p in predictions:
        if not p['correct']:
            key = f"{p['label']!r} -> {p['text']!r}"
            confusions[key] = confusions.get(key, 0) + 1
    return {'count': len(predictions),
            'exact_accuracy': sum(p['correct'] for p in predictions) / len(predictions),
            'review_rate': sum(p['needs_review'] for p in predictions) / len(predictions),
            'accepted_accuracy': sum(p['correct'] for p in accepted) / len(accepted) if accepted else None,
            'groups': groups, 'confusions': confusions, 'predictions': predictions}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--max-mark', type=int)
    parser.add_argument('--confidence-threshold', type=float, default=.8)
    parser.add_argument('--model-dir')
    parser.add_argument('--output', type=Path, default=Path('outputs/evaluation/baseline.json'))
    args = parser.parse_args()
    config = RecognitionConfig(model_dir=args.model_dir, confidence_threshold=args.confidence_threshold)
    report = evaluate(args.manifest, MarkRecognizer(config), args.max_mark)
    report.update(model=config.model_name, confidence_threshold=config.confidence_threshold)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'predictions'}, indent=2))


if __name__ == '__main__':
    main()
