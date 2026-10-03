"""Device selection, reproducibility, and versioned checkpoint loading."""
from dataclasses import asdict
from pathlib import Path
import os
import random
import numpy as np
import torch
from .config import (CHECKPOINT_VERSION, VOCABULARY, BLANK_INDEX,
                     ModelConfig, PreprocessingConfig)
from .model import MarksCRNN


def select_device(request='auto'):
    if request not in ('auto', 'cpu', 'cuda'):
        raise ValueError('Device must be auto, cpu, or cuda')
    return torch.device('cuda' if request != 'cpu' and torch.cuda.is_available() else 'cpu')


def seed_everything(seed):
    # Set before CUDA context initialization for deterministic cuBLAS operations.
    os.environ.setdefault('CUBLAS_WORKSPACE_CONFIG', ':4096:8')
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True
    torch.use_deterministic_algorithms(True, warn_only=True)


def save_checkpoint(path, model, preprocessing, **metadata):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        'format_version': CHECKPOINT_VERSION,
        'vocabulary': VOCABULARY, 'blank_index': BLANK_INDEX,
        'model_config': asdict(model.config),
        'preprocessing_config': asdict(preprocessing),
        'model_state': {key: value.detach().cpu() for key, value in model.state_dict().items()},
        **metadata,
    }
    temporary = path.with_suffix(path.suffix + '.tmp')
    torch.save(payload, temporary)
    temporary.replace(path)


def load_checkpoint(path, device='auto'):
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(f'No trained checkpoint at {path}. Supply weights or train on labeled cells first.')
    payload = torch.load(path, map_location='cpu', weights_only=True)
    if (payload.get('format_version') != CHECKPOINT_VERSION or
            payload.get('vocabulary') != VOCABULARY or payload.get('blank_index') != BLANK_INDEX):
        raise ValueError('Checkpoint format/vocabulary is incompatible with ocr/')
    model = MarksCRNN(ModelConfig(**payload['model_config']))
    model.load_state_dict(payload['model_state'])
    model.to(select_device(device)).eval()
    preprocessing = PreprocessingConfig(**payload['preprocessing_config'])
    return model, preprocessing, payload
