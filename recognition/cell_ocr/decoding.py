"""CTC decoding and mark policy, independent of the model framework."""
import math
import re
from dataclasses import asdict, dataclass

VOCABULARY = "0123456789"
BLANK = 0


def encode(text: str) -> list[int]:
    if re.fullmatch(r"[0-9]{1,2}", text) is None:
        raise ValueError("Labels must contain one or two ASCII digits")
    return [VOCABULARY.index(char) + 1 for char in text]


def greedy_decode(path: list[int]) -> str:
    result = []
    previous = BLANK
    for token in path:
        if not 0 <= token <= 10:
            raise ValueError("Unknown CTC token")
        if token != BLANK and token != previous:
            result.append(VOCABULARY[token - 1])
        previous = token
    return "".join(result)


def sequence_log_probability(log_probs: list[list[float]], text: str) -> float:
    """Sum all CTC alignments for text in log space using the forward algorithm."""
    labels = encode(text)
    states = [BLANK]
    for token in labels:
        states.extend([token, BLANK])
    scores = [-math.inf] * len(states)
    scores[0] = 0.0
    for row in log_probs:
        updated = []
        for i, token in enumerate(states):
            incoming = [scores[i]]
            if i > 0:
                incoming.append(scores[i - 1])
            if i > 1 and token != BLANK and token != states[i - 2]:
                incoming.append(scores[i - 2])
            maximum = max(incoming)
            total = (maximum + math.log(sum(math.exp(v - maximum) for v in incoming))
                     if maximum != -math.inf else -math.inf)
            updated.append(total + row[token])
        scores = updated
    maximum = max(scores[-2:])
    return (maximum + math.log(sum(math.exp(v - maximum) for v in scores[-2:]))
            if maximum != -math.inf else -math.inf)


@dataclass(frozen=True)
class CellResult:
    text: str
    value: int | None
    confidence: float
    valid: bool
    reason: str | None
    requires_review: bool = True

    def to_dict(self):
        return asdict(self)


def validate(text: str, confidence: float, maximum: int = 99) -> CellResult:
    if not 0 <= maximum <= 99:
        raise ValueError("Maximum mark must be between 0 and 99")
    if not math.isfinite(confidence) or not 0 <= confidence <= 1:
        raise ValueError("Confidence must be finite and between 0 and 1")
    if re.fullmatch(r"[0-9]{1,2}", text) is None:
        return CellResult(text, None, confidence, False, "empty_or_invalid_sequence")
    value = int(text)
    if value > maximum:
        return CellResult(text, None, confidence, False, "mark_exceeds_maximum")
    return CellResult(text, value, confidence, True, None)
