# OBE Lens individual-cell recognizer

This Python component recognizes a **previously extracted cell** containing one handwritten integer of one or two digits. It does not detect tables or extract cells. The Flutter app still uses its placeholder OCR service; invoking Python directly from the mobile UI is not supported.

## Architecture and contract

Cell → EXIF correction/transparency compositing → grayscale → aspect-preserving resize and white padding (32×96) → three CNN blocks → 24-step feature sequence → bidirectional LSTM (64 hidden units per direction) → 11 logits → greedy CTC decoding → validation → confidence → teacher review.

Token 0 is the internal CTC blank; tokens 1–10 represent `0123456789`. Decode collapses consecutive repetitions **before** removing blanks, so `11` remains possible. Predictions longer than two digits are rejected rather than truncated. Leading zeros are preserved in `text` and converted normally in `value`.

`predict` emits JSON fields: `text`, `value` (null for invalid predictions), `confidence` (0–1), `valid`, `reason`, and `requires_review`. All results require teacher review. A rubric-specific maximum can be supplied (default 99). Invalid/blank predictions must remain unresolved in downstream integration; do not silently turn them into zero.

Confidence is the CTC probability of the greedy decoded string, computed by summing all alignments with a log-space forward algorithm. It is an uncalibrated model score, not a measured likelihood of correctness. Invalid-length/blank outputs have confidence zero. Greedy decoding may miss the most probable sequence; validation does not force the network to output a valid mark.

## Setup, training, and prediction

From the repository root:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ./recognition --extra-index-url https://download.pytorch.org/whl/cpu
python -m unittest discover -s recognition/tests -v
cell-ocr train --train data/train.csv --validation data/validation.csv --output recognition/checkpoints/best.pt --epochs 30
cell-ocr predict --checkpoint recognition/checkpoints/best.pt --image data/cells/cell_20.png --maximum 25
```

Manifest format (paths relative to each CSV file):

```csv
image_path,label
cells/cell_0.png,0
cells/cell_15.png,15
cells/cell_20.png,20
```

Use real labeled handwriting crops with grid borders excluded. Keep training, validation, and final test writers/sheets separate; the loader checks overlapping paths but cannot infer writer identity or detect duplicate content. Include zeros, repeated digits, and the whole deployed mark range. Preprocessing is shared by training and inference. Heavy border removal is intentionally left to cell extraction to avoid erasing strokes.

Training uses CPU PyTorch, Adam, CTC loss, gradient clipping, a fixed seed, and exact-string validation accuracy. The best validation checkpoint contains weights, a format version, seed, and validation accuracy. No pretrained checkpoint or dataset is bundled. Tests establish software behavior, not handwriting accuracy.

## Acceptance before deployment

Evaluate an untouched test set and report exact-mark accuracy, results for single/two-digit marks, repeated digits, and confusion pairs. Compare confidence to correctness on held-out data before selecting any review thresholds. Check blank, noisy, cropped, and out-of-domain cells. Preserve cell coordinates and original crops in the future table adapter so teachers can review each prediction. Feed accepted text and per-cell confidence into Flutter through a separate API or an explicitly supported mobile model runtime; never mark OCR results as teacher-verified automatically.

CTC loss tensor conventions follow the [official PyTorch CTCLoss documentation](https://docs.pytorch.org/docs/stable/generated/torch.nn.CTCLoss.html): time-major log probabilities, digit-only targets, and a separate blank index.
