# OBE Lens OCR

An isolated PyTorch implementation for **already-extracted handwritten integer cells**. Flutter source and dependencies are unchanged. No dataset or trained model is supplied. Training creates `models/marks_crnn.pth`; prediction requires this checkpoint and fails explicitly if it is missing.

## Repository inspection and placement

The app uses `lib/screens/image_source_screen.dart` to pick a camera/gallery `XFile` at quality 92. Its path passes to `ImageProcessingScreen`, `BaseOcrService.processImage`, and `VerificationScreen`. The app does not copy these files to a durable image store or extract table cells. `PlaceholderOcrService` returns an empty table for manual entry.

`MarksTableData` stores question → part → text, image path, table-level confidence, and verification status. `VerificationScreen` renders questions 1–4 or 5–8 and parts a–g, computes totals, and accepts teacher edits. Existing review behavior accepts decimals, maps invalid input to N/A, and mirrors edits between question groups. It has no correction-image store or per-cell confidence field. This module does not change those behaviors.

The previous `recognition/cell_ocr/` prototype remains available. It has its own packaging and basic CPU training/inference. Use `ocr/` for the configurable implementation described here. The checkpoint formats are different: the older prototype's weights must not be passed to this module directly.

```text
ocr/
  config.py           vocabulary and preprocessing/model/training/inference settings
  preprocessing.py    file/PIL/NumPy loading, trimming, filtering, resize, pad, normalize
  dataset.py          CSV loading, group-aware splitting, CTC batch collation
  model.py            lightweight CNN → BiLSTM → 11 logits
  ctc.py              encode_label, decode_prediction, CTC loss, sequence probability
  train.py            supervised training and checkpoint selection
  evaluate.py         held-out metrics, subgroups, confusions, predictions
  inference.py        MarkRecognizer and predict_mark
  validation.py       per-question limits and confidence review policy
  corrections.py      explicit image/label correction storage and CSV export
  table_processing.py adapter for supplied cells and question/part identities
  metrics.py          shared CER and evaluation metrics
  runtime.py          devices, seeds, versioned checkpoint persistence
  tests/              synthetic software tests; no accuracy claim
models/
  marks_crnn.pth       generated after training, not a bundled random model
data/
  train/
  val/
  test/
  corrections/
```

## Install and verify without a dataset

Run from the repository root, using Python 3.10 or newer:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r ocr/requirements.txt
python -m unittest discover -s ocr/tests -v
python -m ocr.train --help
python -m ocr.evaluate --help
python -m ocr.inference --help
```

For CPU-only installation, install PyTorch from its CPU wheel index first, then the requirements:

```bash
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install -r ocr/requirements.txt
```

For CUDA, use a CUDA-enabled PyTorch installation compatible with the laptop GPU and driver. Training selects CUDA automatically when available and falls back to CPU otherwise, including when `--device cuda` is requested on a machine without CUDA. NumPy arrays are accepted directly; OpenCV is not a required dependency.

The tests generate temporary synthetic images and exercise preprocessing, training, evaluation, checkpoint loading, inference, confidence, and correction export. They do not produce a deployment checkpoint or establish handwriting accuracy. Actual recognition needs your later dataset and training, or compatible pretrained weights.

## Data contract

Put crops in the split directories and a `labels.csv` in each directory:

```csv
image_path,label,group
cell_0.png,0,writer_01
cell_15.png,15,writer_02
cell_20.png,20,writer_03
```

`image_path` is relative to the CSV; absolute paths also work. `label` is a string of one or two ASCII digits. Leading zeros are preserved. `group` is optional, but if used for automatic splitting it must be provided for every sample. Use a writer identifier for writer-independent evaluation, or sheet identifier for sheet-independent evaluation. Training with separate manifests rejects overlapping image paths and provided groups. It cannot identify duplicate image content or infer writer identity when groups are omitted.

With separate validation data:

```bash
python -m ocr.train --train data/train/labels.csv --val data/val/labels.csv --epochs 30 --batch-size 32 --learning-rate 0.001 --output models/marks_crnn.pth
```

With one manifest and an automatic split:

```bash
python -m ocr.train --train data/all.csv --validation-fraction 0.2 --seed 42
```

Group-based splitting approximates the requested validation fraction by **number of groups**; uneven group sizes may produce a different sample fraction. Keep the final test set separate. Automatic splitting without groups prevents path overlap, but does not guarantee writer separation.

Training uses AdamW, configurable learning rate/weight decay/batch size, CTC loss, gradient clipping, and seeded Python/NumPy/PyTorch randomness. CUDA determinism is requested; some device kernels may still warn about nondeterminism, and identical results across hardware/software versions are not guaranteed.

Each epoch logs training loss, validation loss, exact sequence accuracy, and corpus character error rate (edit distance divided by total reference characters). CER may exceed 1 for long incorrect outputs. Every epoch is saved to `models/marks_crnn_checkpoints/`; `history.json` records metrics and `split.json` records split membership. The best checkpoint is selected by highest validation exact accuracy, breaking ties with lower validation loss. Checkpoints contain weights, optimizer state, configuration, and epoch metrics; automatic resume is not implemented.

## Preprocessing and model

The shared pipeline composites transparency on white, applies EXIF orientation, converts to grayscale, optionally uses a median filter, trims foreground bounds with a configurable margin, optionally thresholds, resizes **without stretching**, pads, and normalizes white to -1 and dark ink to +1. Blank images retain their white background. Trimming assumes dark handwriting on a light background; grid-border removal belongs to extraction. Disable trimming for crops where faint strokes or noise make foreground bounds unreliable.

Defaults are height 32, width 96, padding 2, trimming enabled, whitespace threshold 240, crop margin 2, binary threshold disabled, and noise filtering disabled. Color arrays default to BGR/BGRA (OpenCV order); set `array_color_order="RGB"` for RGB/RGBA arrays. Arrays must be nonempty `uint8`, with 1, 3, or 4 channels (or two-dimensional grayscale).

Configure preprocessing through Python or a JSON file passed to training:

```json
{
  "height": 32,
  "width": 96,
  "padding": 2,
  "trim_whitespace": true,
  "whitespace_threshold": 240,
  "crop_margin": 2,
  "threshold": null,
  "median_filter_size": 0,
  "array_color_order": "BGR"
}
```

```bash
python -m ocr.train --train data/train/labels.csv --val data/val/labels.csv --preprocessing-config preprocessing.json
```

Inference and evaluation automatically restore preprocessing from the checkpoint. The default model has three small convolution blocks, width downsampling by 4, height averaging, a bidirectional LSTM with 64 hidden units per direction, and a linear output. A 32×96 input gives 24 sequence steps and fewer than 300,000 parameters. `ModelConfig(hidden_size=...)` configures the LSTM through the Python training API.

Vocabulary is `0123456789`, with blank at index 0 and digits at indices 1–10:

```python
from ocr.ctc import encode_label, decode_prediction

encode_label("15")                 # [2, 6] — digit '1', then digit '5'
decode_prediction([2, 2, 0, 6, 6]) # '15'
decode_prediction([2, 2, 0, 2])    # '11'
```

Repeated tokens collapse before blanks are removed. `decode_prediction` accepts a token sequence or one cell's time-major Torch/NumPy logits `[T, 11]`. Training targets never contain blank. The loss uses time-major `[T, N, 11]` logits following [PyTorch CTCLoss conventions](https://docs.pytorch.org/docs/stable/generated/torch.nn.CTCLoss.html).

## Evaluation

```bash
python -m ocr.evaluate --test data/test/labels.csv --checkpoint models/marks_crnn.pth --output models/test_report.json
```

The report includes loss, exact sequence accuracy, CER, one-/two-digit and repeated-digit subgroups, confusion counts, and each prediction. Do not use the final test set for model selection. Before deployment, measure handwriting accuracy and confidence calibration on held-out writers, including blank, noisy, clipped, and out-of-domain cells.

## Single-cell inference

```python
from ocr import predict_mark

result = predict_mark("cell_15.png", max_mark=20, confidence_threshold=0.8)
# Example shape only; real values depend on trained weights:
# {"text": "15", "value": 15, "confidence": 0.96,
#  "valid": True, "reason": None, "needs_review": False}
```

Reuse a recognizer to avoid loading the weights for every crop:

```python
from ocr.config import InferenceConfig
from ocr.inference import MarkRecognizer

recognizer = MarkRecognizer("models/marks_crnn.pth",
                            config=InferenceConfig(confidence_threshold=0.85))
result = recognizer.predict_mark(cropped_bgr_numpy_image, max_mark=10)
```

```bash
python -m ocr.inference cell_15.png --max-mark 20 --confidence-threshold 0.85
```

`validate_mark(text, max_mark=None)` accepts only one or two ASCII digits. No global maximum is hardcoded. A supplied maximum must be a nonnegative integer. Invalid predictions retain `text`, return `value=None`, and always need review. Low-confidence valid predictions retain both their text and integer; no guessed replacement is made. `needs_review=False` means the configured score threshold was met, **not** that a teacher verified the mark.

Confidence sums all CTC alignments for the greedily decoded string in log space. It is an uncalibrated model score, not measured accuracy. Greedy decoding may miss the globally most probable string. Blank or overlength outputs receive confidence zero. A high score alone does not establish in-domain handwriting validity.

## Teacher corrections and marks-table boundary

```python
from ocr.corrections import save_correction, export_corrections

record = save_correction(cropped_bgr_numpy_image,
                         predicted="18", confidence=0.62, corrected="16",
                         max_mark=20, group="writer_01",
                         metadata={"question": "1", "part": "a"})
# Only after selecting/reviewing records:
export_corrections([record], "data/corrections/labels.csv")
```

Each explicit save creates a unique original crop PNG and JSON record containing prediction, confidence, correction, optional rubric maximum, writer/sheet group, timestamp, and metadata. Preserve writer grouping when curating corrections. These records are not automatically added to training; there is no online learning or reinforcement learning.

```python
from ocr.table_processing import ExtractedCell, process_cells

payload = process_cells([
    ExtractedCell("1", "a", "cell_1a.png", max_mark=20, bounds=(10, 20, 80, 60)),
    ExtractedCell("2", "a", "cell_2a.png", max_mark=10),
], recognizer, table_type="1-4", image_path="sheet.png")
```

The adapter maps supplied crops into question/part cells, preserves raw predictions and review details in `cellResults`, retains optional original-image coordinates, and leaves `isVerified=False`. Missing/invalid cells have an empty mark and review reason; they never become guessed numeric zeros. Low-confidence valid text remains visible with its review flag. The table confidence is an average model score over the expected grid, with missing cells contributing zero.

This is a **Python integration boundary**, not a deployed backend or live Flutter connection. Future table extraction must provide the crops. A future `BaseOcrService` implementation can map `tableType`, `cellMarks`, `imagePath`, and `confidenceScore` into `MarksTableData` via a chosen API/runtime. It must also preserve and expose `cellResults` review flags and crops. The existing UI labels confidence as “OCR Accuracy” and counts N/A as zero; those are existing behaviors to revisit when connecting the recognizer. Do not treat unresolved totals as final or set `isVerified` automatically.
