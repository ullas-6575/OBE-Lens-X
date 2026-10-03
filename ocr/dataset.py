"""CSV datasets and deterministic, optionally writer-grouped splits."""
import csv
from dataclasses import dataclass
from pathlib import Path
import random
from torch.utils.data import Dataset
import torch
from .config import PreprocessingConfig
from .ctc import encode_label
from .preprocessing import preprocess


@dataclass(frozen=True)
class Sample:
    image_path: Path
    label: str
    group: str | None = None


class CellDataset(Dataset):
    def __init__(self, manifest=None, *, samples=None, preprocessing=PreprocessingConfig()):
        self.preprocessing = preprocessing
        if (manifest is None) == (samples is None):
            raise ValueError('Provide exactly one of manifest or samples')
        if manifest is not None:
            manifest = Path(manifest)
            with manifest.open(newline='', encoding='utf-8') as stream:
                reader = csv.DictReader(stream)
                if not {'image_path', 'label'}.issubset(reader.fieldnames or []):
                    raise ValueError('CSV requires image_path,label columns')
                self.samples = [Sample((manifest.parent / row['image_path']).resolve(),
                                       row['label'], row.get('group') or None) for row in reader]
        else:
            self.samples = list(samples)
        if not self.samples:
            raise ValueError('Dataset is empty; add labeled cells before training')
        paths = set()
        for sample in self.samples:
            encode_label(sample.label)
            if not sample.image_path.is_file():
                raise ValueError(f'Missing cell image: {sample.image_path}')
            if sample.image_path in paths:
                raise ValueError(f'Duplicate cell path: {sample.image_path}')
            paths.add(sample.image_path)

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index):
        sample = self.samples[index]
        return preprocess(sample.image_path, self.preprocessing), sample.label


def collate_cells(samples):
    images, labels = zip(*samples)
    targets = torch.tensor([token for text in labels for token in encode_label(text)], dtype=torch.long)
    lengths = torch.tensor([len(text) for text in labels], dtype=torch.long)
    return torch.stack(images), targets, lengths, labels


def ensure_disjoint(training, validation):
    if {s.image_path for s in training.samples} & {s.image_path for s in validation.samples}:
        raise ValueError('Training and validation image paths overlap')
    train_groups = {s.group for s in training.samples if s.group is not None}
    val_groups = {s.group for s in validation.samples if s.group is not None}
    if train_groups & val_groups:
        raise ValueError('Training and validation groups overlap')


def split_dataset(dataset, validation_fraction=0.2, seed=42):
    if not 0 < validation_fraction < 1:
        raise ValueError('Validation fraction must be between zero and one')
    groups = {}
    grouped = [sample.group is not None for sample in dataset.samples]
    if any(grouped) and not all(grouped):
        raise ValueError('Provide groups for every sample, or omit groups entirely')
    for sample in dataset.samples:
        key = sample.group if sample.group is not None else str(sample.image_path)
        groups.setdefault(key, []).append(sample)
    keys = sorted(groups)
    if len(keys) < 2:
        raise ValueError('At least two samples/groups are needed for a split')
    random.Random(seed).shuffle(keys)
    count = max(1, min(len(keys) - 1, round(len(keys) * validation_fraction)))
    validation_keys = set(keys[:count])
    training = [s for key, values in groups.items() if key not in validation_keys for s in values]
    validation = [s for key, values in groups.items() if key in validation_keys for s in values]
    return (CellDataset(samples=training, preprocessing=dataset.preprocessing),
            CellDataset(samples=validation, preprocessing=dataset.preprocessing))
