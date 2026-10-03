import csv
from pathlib import Path
from PIL import Image
import torch
from torch.utils.data import Dataset
from .decoding import encode
from .preprocessing import preprocess


class CellDataset(Dataset):
    """CSV image_path,label; relative paths resolve against the CSV directory."""

    def __init__(self, manifest):
        manifest = Path(manifest)
        self.samples = []
        with manifest.open(newline="", encoding="utf-8") as stream:
            reader = csv.DictReader(stream)
            if not {"image_path", "label"}.issubset(reader.fieldnames or []):
                raise ValueError("CSV requires image_path,label columns")
            for row in reader:
                label = row["label"]
                encode(label)
                path = (manifest.parent / row["image_path"]).resolve()
                if not path.is_file():
                    raise ValueError(f"Missing cell image: {path}")
                self.samples.append((path, label))
        if not self.samples:
            raise ValueError("Dataset is empty")

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index):
        path, label = self.samples[index]
        with Image.open(path) as image:
            tensor = preprocess(image)
        return tensor, label


def collate(samples):
    images, labels = zip(*samples)
    targets = torch.tensor([token for label in labels for token in encode(label)], dtype=torch.long)
    lengths = torch.tensor([len(label) for label in labels], dtype=torch.long)
    return torch.stack(images), targets, lengths, labels
