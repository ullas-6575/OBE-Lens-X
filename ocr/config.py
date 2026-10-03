"""Versioned vocabulary and validated OCR configuration."""
from dataclasses import dataclass
from pathlib import Path
import math

VOCABULARY = "0123456789"
BLANK_INDEX = 0
NUM_CLASSES = len(VOCABULARY) + 1
CHAR_TO_INDEX = {char: index + 1 for index, char in enumerate(VOCABULARY)}
INDEX_TO_CHAR = {index: char for char, index in CHAR_TO_INDEX.items()}
CHECKPOINT_VERSION = 1
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CHECKPOINT = PROJECT_ROOT / "models" / "marks_crnn.pth"


@dataclass(frozen=True)
class PreprocessingConfig:
    height: int = 32
    width: int = 96
    padding: int = 2
    trim_whitespace: bool = True
    whitespace_threshold: int = 240
    crop_margin: int = 2
    threshold: int | None = None
    median_filter_size: int = 0
    array_color_order: str = "BGR"

    def __post_init__(self):
        if self.height < 8 or self.width < 16:
            raise ValueError("Input height >= 8 and width >= 16 are required")
        if self.padding < 0 or 2 * self.padding >= min(self.height, self.width):
            raise ValueError("Padding must leave a positive image area")
        if self.crop_margin < 0:
            raise ValueError("Crop margin must be nonnegative")
        for value in [self.whitespace_threshold, self.threshold]:
            if value is not None and (not isinstance(value, int) or not 0 <= value <= 255):
                raise ValueError("Pixel thresholds must be integers between 0 and 255")
        if self.median_filter_size != 0 and (self.median_filter_size < 3 or self.median_filter_size % 2 == 0):
            raise ValueError("Median filter size must be zero or an odd integer >= 3")
        if self.array_color_order not in ("BGR", "RGB"):
            raise ValueError("Array color order must be BGR or RGB")


@dataclass(frozen=True)
class ModelConfig:
    hidden_size: int = 64

    def __post_init__(self):
        if self.hidden_size < 1:
            raise ValueError("Hidden size must be positive")


@dataclass(frozen=True)
class TrainingConfig:
    epochs: int = 30
    batch_size: int = 32
    learning_rate: float = 0.001
    weight_decay: float = 0.0001
    seed: int = 42
    validation_fraction: float = 0.2
    device: str = "auto"
    num_workers: int = 0

    def __post_init__(self):
        if self.epochs < 1 or self.batch_size < 1 or self.num_workers < 0:
            raise ValueError("Epochs/batch size must be positive; workers nonnegative")
        if not isinstance(self.seed, int) or not 0 <= self.seed < 2**32:
            raise ValueError("Seed must be an integer between 0 and 2**32 - 1")
        if not math.isfinite(self.learning_rate) or self.learning_rate <= 0:
            raise ValueError("Learning rate must be finite and positive")
        if not math.isfinite(self.weight_decay) or self.weight_decay < 0:
            raise ValueError("Weight decay must be finite and nonnegative")
        if not 0 < self.validation_fraction < 1:
            raise ValueError("Validation fraction must be between zero and one")
        if self.device not in ("auto", "cpu", "cuda"):
            raise ValueError("Device must be auto, cpu, or cuda")


@dataclass(frozen=True)
class InferenceConfig:
    confidence_threshold: float = 0.8
    device: str = "auto"

    def __post_init__(self):
        if not math.isfinite(self.confidence_threshold) or not 0 <= self.confidence_threshold <= 1:
            raise ValueError("Confidence threshold must be between zero and one")
        if self.device not in ("auto", "cpu", "cuda"):
            raise ValueError("Device must be auto, cpu, or cuda")
