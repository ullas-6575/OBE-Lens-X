"""Reproduce an explicitly limited handwritten evaluation on the bundled sheet."""
import argparse
import json
from pathlib import Path
from time import perf_counter
import cv2
from ocr import MarkRecognizer
from ocr.config import RecognitionConfig
from ocr.cell_extractor import extract_cells


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-dir', default=str(root / 'models/pretrained/en_PP-OCRv5_mobile_rec'))
    args = parser.parse_args()
    reference_file = root / 'evaluation/sample_reference.json'
    reference = json.loads(reference_file.read_text())
    extraction = extract_cells(reference_file.parent / reference['source'])
    recognizer = MarkRecognizer(RecognitionConfig(model_dir=args.model_dir))
    predictions = []
    crop_dir = root / 'outputs/cells/sample'
    crop_dir.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(crop_dir / 'rectified.png'), extraction.image)
    for cell in extraction.cells:
        key = f'{cell.question}_{cell.part}'
        cv2.imwrite(str(crop_dir / f'{key}.png'), cell.image)
        start = perf_counter()
        result = recognizer.predict_mark(cell.image)
        result.update(cell=key, elapsed_ms=round((perf_counter()-start)*1000, 2))
        if key in reference['numeric']:
            label = reference['numeric'][key]
            result.update(reference=label, exact_correct=result['text'] == label,
                          value_correct=result['value'] == int(label))
        elif key in reference['blank']:
            result.update(reference='', blank_correct=result['value'] is None)
        else:
            result.update(excluded=reference['excluded'][key])
        predictions.append(result)
    numeric = [p for p in predictions if 'exact_correct' in p]
    blank = [p for p in predictions if 'blank_correct' in p]
    report = {
        'model': recognizer.config.model_name,
        'provenance': reference['provenance'],
        'extracted_cells': len(predictions), 'numeric_count': len(numeric),
        'numeric_exact_accuracy': sum(p['exact_correct'] for p in numeric)/len(numeric),
        'numeric_value_accuracy': sum(p['value_correct'] for p in numeric)/len(numeric),
        'blank_count': len(blank),
        'blank_unresolved_rate': sum(p['blank_correct'] for p in blank)/len(blank),
        'blank_numeric_hallucinations': sum(not p['blank_correct'] for p in blank),
        'review_count': sum(p['needs_review'] for p in predictions),
        'excluded_count': len(reference['excluded']),
        'predictions': predictions,
    }
    output = root / 'evaluation/sample_report.json'
    output.write_text(json.dumps(report, indent=2))
    print(json.dumps({k:v for k,v in report.items() if k != 'predictions'}, indent=2))


if __name__ == '__main__':
    main()
