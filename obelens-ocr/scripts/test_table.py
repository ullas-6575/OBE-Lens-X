"""Recognize a full OBE rubric and save crop evidence with the JSON result."""
import argparse
import json
from pathlib import Path
import cv2
from ocr import MarkRecognizer
from ocr.config import RecognitionConfig
from ocr.cell_extractor import extract_cells
from ocr.full_table import process_table


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--table-type', choices=['1-4', '5-8'], default='1-4')
    parser.add_argument('--model-dir', default='models/pretrained/en_PP-OCRv5_mobile_rec')
    parser.add_argument('--max-mark', type=int)
    parser.add_argument('--corners', help='JSON corners in TL,TR,BR,BL order')
    parser.add_argument('--output', type=Path, default=Path('outputs/predictions/table.json'))
    args = parser.parse_args()
    corners = json.loads(args.corners) if args.corners else None
    recognizer = MarkRecognizer(RecognitionConfig(model_dir=args.model_dir))
    result = process_table(args.image, recognizer, table_type=args.table_type,
                           corners=corners, max_mark=args.max_mark)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2))
    extraction = extract_cells(args.image, table_type=args.table_type, corners=corners)
    crop_dir = args.output.parent / f'{args.output.stem}_cells'
    crop_dir.mkdir(exist_ok=True)
    cv2.imwrite(str(crop_dir / 'rectified.png'), extraction.image)
    for cell in extraction.cells:
        cv2.imwrite(str(crop_dir / f'{cell.question}_{cell.part}.png'), cell.image)
    print(f'Saved {len(extraction.cells)} cells and results to {args.output}')


if __name__ == '__main__':
    main()
