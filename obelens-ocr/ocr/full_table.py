"""Full-table recognition with crop evidence and original-image coordinates."""
import base64
import cv2
from .cell_extractor import extract_cells
from .table_processor import process_cells


def process_table(image, recognizer, *, table_type='1-4', corners=None, max_mark=None):
    extraction = extract_cells(image, table_type=table_type, corners=corners, max_mark=max_mark)
    payload = process_cells(extraction.cells, recognizer, table_type=table_type)
    for cell in extraction.cells:
        ok, encoded = cv2.imencode('.png', cell.image)
        if not ok:
            raise RuntimeError('Could not encode crop')
        payload['cellResults'][cell.question][cell.part]['crop_base64'] = base64.b64encode(encoded).decode('ascii')
    payload['tableCorners'] = extraction.corners
    return payload
