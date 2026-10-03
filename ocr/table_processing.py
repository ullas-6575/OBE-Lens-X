"""Adapter for already-extracted cells; table detection and transport are external."""
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from .preprocessing import ImageInput

PARTS = tuple('abcdefg')
TABLE_QUESTIONS = {'1-4': ('1', '2', '3', '4'), '5-8': ('5', '6', '7', '8')}


@dataclass(frozen=True)
class ExtractedCell:
    question: str
    part: str
    image: ImageInput
    max_mark: int | None = None
    # Coordinates in the original table image: left, top, right, bottom.
    bounds: tuple[int, int, int, int] | None = None


def process_cells(cells, recognizer, *, table_type='1-4', image_path=None):
    if table_type not in TABLE_QUESTIONS:
        raise ValueError('table_type must be 1-4 or 5-8')
    questions = TABLE_QUESTIONS[table_type]
    cell_marks = {question: {part: '' for part in PARTS} for question in questions}
    details = {question: {part: {'text': '', 'value': None, 'confidence': 0.0,
                               'valid': False, 'needs_review': True, 'reason': 'cell_not_supplied'}
                         for part in PARTS} for question in questions}
    seen = set()
    for cell in cells:
        key = (cell.question, cell.part)
        if cell.question not in questions or cell.part not in PARTS:
            raise ValueError(f'Cell {key} is outside the selected table')
        if key in seen:
            raise ValueError(f'Duplicate cell: {key}')
        seen.add(key)
        prediction = recognizer.predict_mark(cell.image, max_mark=cell.max_mark)
        if prediction['valid']:
            cell_marks[cell.question][cell.part] = prediction['text']
        detail = {**prediction, 'max_mark': cell.max_mark, 'bounds': cell.bounds,
                  'crop_path': str(cell.image) if isinstance(cell.image, (str, Path)) else None}
        details[cell.question][cell.part] = detail
    # Average over the complete expected grid; missing cells contribute zero.
    scores = [entry['confidence'] for parts in details.values() for entry in parts.values()]
    return {'tableType': table_type, 'questions': list(questions), 'cellMarks': cell_marks,
            'cellResults': details, 'imagePath': str(image_path) if image_path is not None else None,
            'confidenceScore': sum(scores) / len(scores),
            'needsReview': any(entry['needs_review'] for parts in details.values() for entry in parts.values()),
            'isVerified': False, 'scannedAt': datetime.now(timezone.utc).isoformat()}
