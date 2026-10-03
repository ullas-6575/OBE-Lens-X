# OBE Lens

Flutter marks-table capture and teacher-verification app.

The isolated [OCR module](ocr/README.md) provides configurable PyTorch CRNN + CTC recognition for individual handwritten integer cells, training, evaluation, confidence review, and teacher-correction storage. The dataset and trained weights are still required for real handwriting recognition. The Flutter app retains its existing OCR placeholder.

The earlier [recognition prototype](recognition/README.md) remains available separately.
