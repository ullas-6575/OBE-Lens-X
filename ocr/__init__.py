"""Isolated OBE Lens handwritten integer OCR; no Flutter dependencies."""


def predict_mark(image, max_mark=None, **kwargs):
    """Load the configured checkpoint and recognize one extracted cell."""
    from .inference import predict_mark as predict
    return predict(image, max_mark=max_mark, **kwargs)
