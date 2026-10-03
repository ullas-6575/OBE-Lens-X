"""Conservative blank detection on grid-free cell crops."""
import cv2
import numpy as np


def is_empty_cell(image: np.ndarray) -> bool:
    """Ignore paper shading/sensor specks, but send stroke-like regions to OCR.

    Estimate paper brightness locally and estimate noise from high-frequency
    residuals. Dark/very noisy crops are uncertain and always go to OCR. This
    heuristic needs broader handwriting validation; it never edits the OCR input.
    """
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY).astype(np.float32)
    if float(np.median(gray)) < 80:
        return False
    smooth = cv2.GaussianBlur(gray, (3, 3), 0)
    noise = float(np.median(np.abs(gray - smooth))) * 1.4826
    if noise > 5:
        return False
    background = cv2.GaussianBlur(gray, (0, 0), max(3, min(gray.shape) / 7))
    ink = (background - gray > max(2., 6 * noise)).astype(np.uint8)
    _, _, components, _ = cv2.connectedComponentsWithStats(ink, connectivity=8)
    # Tiny isolated sensor specks do not constitute handwriting.
    return not any(area >= 8 and max(width, height) >= 4
                   for _, _, width, height, area in components[1:])
