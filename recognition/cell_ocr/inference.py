import math
from PIL import Image
import torch
from .decoding import greedy_decode, sequence_log_probability, validate
from .model import CRNN
from .preprocessing import preprocess

FORMAT_VERSION = 1


class CellRecognizer:
    def __init__(self, checkpoint):
        payload = torch.load(checkpoint, map_location="cpu", weights_only=True)
        if payload.get("format_version") != FORMAT_VERSION:
            raise ValueError("Unsupported checkpoint format")
        self.model = CRNN()
        self.model.load_state_dict(payload["model_state"])
        self.model.eval()

    @torch.inference_mode()
    def recognize(self, image: Image.Image, maximum: int = 99):
        log_probs = self.model(preprocess(image).unsqueeze(0)).log_softmax(2)[:, 0]
        text = greedy_decode(log_probs.argmax(1).tolist())
        confidence = 0.0
        if 1 <= len(text) <= 2:
            confidence = min(1.0, math.exp(sequence_log_probability(log_probs.tolist(), text)))
        return validate(text, confidence, maximum)
