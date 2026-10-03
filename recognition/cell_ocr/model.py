import torch
from torch import nn


class CRNN(nn.Module):
    """N×1×32×96 -> T×N×11 unnormalized CTC logits."""

    def __init__(self):
        super().__init__()
        self.cnn = nn.Sequential(
            nn.Conv2d(1, 32, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(32, 64, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(64, 128, 3, padding=1), nn.ReLU(),
            nn.AdaptiveAvgPool2d((1, 24)),
        )
        self.sequence = nn.LSTM(128, 64, bidirectional=True)
        self.classifier = nn.Linear(128, 11)

    def forward(self, images):
        features = self.cnn(images).squeeze(2).permute(2, 0, 1)
        sequence, _ = self.sequence(features)
        return self.classifier(sequence)
