"""Baseline settings; no training or custom neural network."""
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class RecognitionConfig:
    model_name: str = 'en_PP-OCRv5_mobile_rec'
    model_dir: str | None = None
    device: str = 'cpu'
    confidence_threshold: float = 0.8

    def __post_init__(self):
        if not math.isfinite(self.confidence_threshold) or not 0 <= self.confidence_threshold <= 1:
            raise ValueError('confidence_threshold must be between zero and one')
