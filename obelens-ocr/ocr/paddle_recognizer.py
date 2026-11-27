"""Recognition-only PaddleOCR adapter, loaded once and reused across cells."""
import os
from pathlib import Path

from .config import RecognitionConfig
from .preprocessing import prepare_cell
from .empty_cell import is_empty_cell
from .validation import apply_confidence, validate_mark


class MarkRecognizer:
    def __init__(self, config=None, *, backend=None):
        self.config = config or RecognitionConfig()
        self._backend = backend

    def _model(self):
        if self._backend is None:
            if not self.config.model_dir:
                raise ValueError('Provide a local OCR model directory; automatic model downloads are disabled')
            model_dir = Path(self.config.model_dir).expanduser().resolve()
            for name in ('inference.json', 'inference.pdiparams', 'inference.yml'):
                if not (model_dir / name).is_file():
                    raise FileNotFoundError(f'Local OCR model is missing {model_dir / name}; supply the complete inference model')
            os.environ.setdefault('PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK', 'True')
            try:
                from paddleocr import TextRecognition
            except ImportError as exc:
                raise RuntimeError('Install obelens-ocr/requirements.txt in the OCR virtual environment') from exc
            self._backend = TextRecognition(
                model_name=self.config.model_name,
                model_dir=str(model_dir),
                device=self.config.device,
            )
        return self._backend

    def predict_mark(self, image, max_mark=None):
        validate_mark('', max_mark)  # Reject invalid rubric configuration before inference.
        cell = prepare_cell(image)
        if is_empty_cell(cell):
            result = apply_confidence('', 0.0, max_mark=max_mark,
                                      confidence_threshold=self.config.confidence_threshold)
            result.update(reason='empty_cell', empty=True, needs_review=False)
            return result
        predictions = list(self._model().predict(input=cell, batch_size=1))
        if len(predictions) != 1:
            raise RuntimeError('Expected exactly one recognition result per cell')
        prediction = predictions[0]
        # PaddleX Result is a mapping; some serialized responses wrap it in res.
        if 'res' in prediction:
            prediction = prediction['res']
        text = prediction['rec_text']
        if not isinstance(text, str):
            raise RuntimeError('PaddleOCR returned non-string rec_text')
        result = apply_confidence(text, float(prediction['rec_score']), max_mark=max_mark,
                                  confidence_threshold=self.config.confidence_threshold)
        result['empty'] = False
        return result
