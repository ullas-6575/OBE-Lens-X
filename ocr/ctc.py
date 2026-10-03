"""Digit encoding and CTC decoding; blank is never a training label."""
import math
import re
from .config import BLANK_INDEX, CHAR_TO_INDEX, INDEX_TO_CHAR, NUM_CLASSES


def encode_label(text: str) -> list[int]:
    if not isinstance(text, str) or re.fullmatch(r'[0-9]{1,2}', text) is None:
        raise ValueError('Labels must be one or two ASCII digits')
    return [CHAR_TO_INDEX[char] for char in text]


def decode_prediction(prediction) -> str:
    """Decode token IDs [T], or one cell's logits/probabilities [T, C]."""
    if hasattr(prediction, 'ndim'):
        if prediction.ndim == 2:
            if prediction.shape[1] != NUM_CLASSES:
                raise ValueError('Expected 11 CTC classes')
            # Both torch tensors and NumPy arrays support argmax on dimension 1.
            prediction = prediction.argmax(1)
        if prediction.ndim != 1:
            raise ValueError('Expected token IDs [T] or logits [T, 11]')
        prediction = prediction.tolist()
    previous = BLANK_INDEX
    output = []
    for token in prediction:
        if not isinstance(token, int) or not 0 <= token < NUM_CLASSES:
            raise ValueError('Unknown CTC token')
        if token != BLANK_INDEX and token != previous:
            output.append(INDEX_TO_CHAR[token])
        previous = token
    return ''.join(output)


def sequence_log_probability(log_probs: list[list[float]], text: str) -> float:
    """CTC forward algorithm: sum probabilities of all alignments to text."""
    states = [BLANK_INDEX]
    for token in encode_label(text):
        states.extend([token, BLANK_INDEX])
    scores = [-math.inf] * len(states)
    scores[0] = 0.0
    for row in log_probs:
        updated = []
        for i, token in enumerate(states):
            incoming = [scores[i]]
            if i > 0:
                incoming.append(scores[i - 1])
            if i > 1 and token != BLANK_INDEX and token != states[i - 2]:
                incoming.append(scores[i - 2])
            maximum = max(incoming)
            total = (maximum + math.log(sum(math.exp(v - maximum) for v in incoming))
                     if maximum != -math.inf else -math.inf)
            updated.append(total + row[token])
        scores = updated
    maximum = max(scores[-2:])
    return (maximum + math.log(sum(math.exp(v - maximum) for v in scores[-2:]))
            if maximum != -math.inf else -math.inf)


def ctc_loss(logits, targets, target_lengths):
    """Logits [T,N,C]; concatenated targets exclude blanks."""
    import torch
    if logits.ndim != 3 or logits.size(2) != NUM_CLASSES:
        raise ValueError('Expected time-major [T, N, 11] logits')
    if target_lengths.numel() != logits.size(1) or target_lengths.sum().item() != targets.numel():
        raise ValueError('Target lengths do not match the batch')
    if not bool(((targets >= 1) & (targets < NUM_CLASSES)).all()):
        raise ValueError('CTC targets must be digit tokens, never blank')
    input_lengths = torch.full((logits.size(1),), logits.size(0), dtype=torch.long)
    return torch.nn.functional.ctc_loss(logits.log_softmax(2), targets,
                                       input_lengths, target_lengths.cpu(), blank=BLANK_INDEX)
