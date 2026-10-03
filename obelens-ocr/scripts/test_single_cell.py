"""Run from obelens-ocr: python -m scripts.test_single_cell cell.png."""
import argparse
import json
from ocr import MarkRecognizer
from ocr.config import RecognitionConfig


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image')
    parser.add_argument('--max-mark', type=int)
    parser.add_argument('--confidence-threshold', type=float, default=0.8)
    parser.add_argument('--model-dir')
    parser.add_argument('--device', default='cpu')
    args = parser.parse_args()
    recognizer = MarkRecognizer(RecognitionConfig(model_dir=args.model_dir, device=args.device,
                                                  confidence_threshold=args.confidence_threshold))
    print(json.dumps(recognizer.predict_mark(args.image, max_mark=args.max_mark), indent=2))


if __name__ == '__main__':
    main()
