"""Settings for inference with the bundled fine-tuned OCR model."""
from dataclasses import dataclass
import math
from pathlib import Path


@dataclass(frozen=True)
class RecognitionConfig:
    model_name: str = 'obelens'
    model_dir: str | None = str(Path(__file__).resolve().parents[1] / 'models/recognition')
    device: str = 'cpu'
    confidence_threshold: float = 0.8

    def __post_init__(self):
        if not math.isfinite(self.confidence_threshold) or not 0 <= self.confidence_threshold <= 1:
            raise ValueError('confidence_threshold must be between zero and one')
