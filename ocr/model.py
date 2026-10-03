"""Small CNN + bidirectional LSTM for time-major CTC logits."""
from torch import nn
from .config import ModelConfig, NUM_CLASSES


class MarksCRNN(nn.Module):
    def __init__(self, config: ModelConfig = ModelConfig()):
        super().__init__()
        self.config = config
        self.cnn = nn.Sequential(
            nn.Conv2d(1, 32, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(32, 64, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(64, 128, 3, padding=1), nn.ReLU(),
        )
        self.sequence = nn.LSTM(128, config.hidden_size, bidirectional=True)
        self.classifier = nn.Linear(config.hidden_size * 2, NUM_CLASSES)

    def forward(self, images):
        if images.ndim != 4 or images.size(1) != 1 or images.size(2) < 8 or images.size(3) < 16:
            raise ValueError('Expected grayscale images [N, 1, H>=8, W>=16]')
        # Pool only height. Horizontal positions remain the CTC time dimension.
        features = self.cnn(images).mean(dim=2).permute(2, 0, 1)
        sequence, _ = self.sequence(features)
        return self.classifier(sequence)
