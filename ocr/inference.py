"""Checkpoint-backed single-cell recognition; no guessed fallback values."""
import math
import torch
from .config import DEFAULT_CHECKPOINT, InferenceConfig
from .ctc import decode_prediction, sequence_log_probability
from .preprocessing import preprocess
from .runtime import load_checkpoint


class MarkRecognizer:
    """Load once and reuse this object for cells from multiple tables."""
    def __init__(self, checkpoint=DEFAULT_CHECKPOINT, *, config=InferenceConfig()):
        self.config = config
        self.model, self.preprocessing, _ = load_checkpoint(checkpoint, config.device)
        self.device = next(self.model.parameters()).device

    @torch.inference_mode()
    def predict_sequence(self, image):
        tensor = preprocess(image, self.preprocessing).unsqueeze(0).to(self.device)
        log_probs = self.model(tensor).log_softmax(2)[:, 0].cpu()
        if not torch.isfinite(log_probs).all():
            raise RuntimeError('Nonfinite model output; inspect checkpoint weights')
        text = decode_prediction(log_probs)
        confidence = 0.0
        if 1 <= len(text) <= 2:
            confidence = min(1.0, math.exp(sequence_log_probability(log_probs.tolist(), text)))
        return {'text': text, 'confidence': confidence}

    def predict_mark(self, image, max_mark=None):
        from .validation import apply_confidence, validate_mark
        # Validate caller policy before doing model work.
        validate_mark('0', max_mark)
        sequence = self.predict_sequence(image)
        return apply_confidence(sequence['text'], sequence['confidence'], max_mark=max_mark,
                                confidence_threshold=self.config.confidence_threshold)


def predict_mark(image, max_mark=None, *, checkpoint=DEFAULT_CHECKPOINT,
                 confidence_threshold=0.8, device='auto'):
    """Convenience API. Use MarkRecognizer for repeated calls to avoid reloading weights."""
    recognizer = MarkRecognizer(checkpoint, config=InferenceConfig(confidence_threshold, device))
    return recognizer.predict_mark(image, max_mark)


def main():
    import argparse
    import json
    parser = argparse.ArgumentParser(description='Recognize one cropped handwritten mark cell')
    parser.add_argument('image')
    parser.add_argument('--checkpoint', default=str(DEFAULT_CHECKPOINT))
    parser.add_argument('--max-mark', type=int)
    parser.add_argument('--confidence-threshold', type=float, default=0.8)
    parser.add_argument('--device', choices=['auto', 'cpu', 'cuda'], default='auto')
    args = parser.parse_args()
    print(json.dumps(predict_mark(args.image, max_mark=args.max_mark, checkpoint=args.checkpoint,
                                 confidence_threshold=args.confidence_threshold, device=args.device)))


if __name__ == '__main__':
    main()
