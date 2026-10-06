"""Question-specific integer validation, independent of image/model code."""
import math
from numbers import Integral
import re


def numeric_mark(text):
    """Keep complete one/two-digit marks; never guess or strip letters."""
    if not isinstance(text, str):
        return None
    text = text.strip()
    return text if re.fullmatch(r'[0-9]{1,2}', text) else None


def validate_mark(predicted_text, max_mark=None):
    if max_mark is not None and (isinstance(max_mark, bool) or
                                not isinstance(max_mark, Integral) or max_mark < 0):
        raise ValueError('max_mark must be a nonnegative integer or None')
    result = {'text': predicted_text, 'value': None, 'valid': False, 'reason': None}
    mark = numeric_mark(predicted_text)
    if mark is None:
        result['reason'] = 'expected_one_or_two_digits'
        return result
    value = int(mark)
    if max_mark is not None and value > max_mark:
        result['reason'] = 'mark_exceeds_maximum'
        return result
    result.update(value=value, valid=True)
    return result


def apply_confidence(predicted_text, confidence, *, max_mark=None, confidence_threshold=0.8):
    if not math.isfinite(confidence) or not 0 <= confidence <= 1:
        raise ValueError('Confidence must be finite and between zero and one')
    if not math.isfinite(confidence_threshold) or not 0 <= confidence_threshold <= 1:
        raise ValueError('Confidence threshold must be finite and between zero and one')
    result = validate_mark(predicted_text, max_mark)
    result['confidence'] = float(confidence)
    result['needs_review'] = not result['valid'] or confidence < confidence_threshold
    return result
