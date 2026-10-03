# OBE Lens OCR

Table photograph → perspective correction → grid extraction → 28 cropped cells →
`en_PP-OCRv5_mobile_rec` → advisory integer validation and confidence flags → Flutter review.
No training or fine-tuning is performed.

## Setup and server

From the repository root, reuse the existing OCR environment:

```bash
source .venv/bin/activate
pip install -r obelens-ocr/requirements.txt
cd obelens-ocr
python -m ocr.server
```

The verified versions are PaddleOCR 3.7.0, CPU PaddlePaddle 3.3.1 and OpenCV 4.10.
The downloaded English model is at `models/pretrained/en_PP-OCRv5_mobile_rec`,
ignored by Git. Supply a different local model path with `--model-dir` if needed.
On a fresh checkout, download the official inference model listed in the
[PaddleOCR documentation](https://www.paddleocr.ai/main/en/version3.x/pipeline_usage/OCR.html)
and extract it there, or use the single-cell script once without `--model-dir`
to populate Paddle's cache and point the server to that model directory.

The service defaults to localhost:8765. It uses one reusable recognizer and
serializes inference requests. Images and crops are processed in memory; the API
does not save uploaded sheets. `--confidence-threshold` defaults to 0.8.
`GET /health` checks the server; the model initializes on first inference.

## Flutter connection

The app's default OCR service now uploads images to `POST /ocr/table`.

- Android emulator debug builds: `flutter run`; the default address is `http://10.0.2.2:8765`.
- Desktop: the default address is `http://127.0.0.1:8765`.
- Physical Android device on the same LAN: start Python with `--host 0.0.0.0`, then
  `flutter run --dart-define=OCR_API_URL=http://YOUR_COMPUTER_LAN_IP:8765`.
- Hosted/release builds and iOS: put the Python API behind HTTPS and pass its base
  URL with `--dart-define=OCR_API_URL=https://your-ocr-host`. Android HTTP access
  is enabled only in the debug manifest. Browser uploads are not implemented.

An optional server `OBELENS_OCR_TOKEN` environment variable enables bearer-token
checking. Supply the matching build-time `--dart-define=OCR_API_TOKEN=...` value
in Flutter. The included server is for local development; it does not provide
TLS, account authentication or a public deployment.

The complete reconstructed table is ready immediately after scanning. Clearly
empty cells show `N/A`. Every nonempty OCR prediction is displayed, including
low-confidence or non-numeric text; confidence and integer validation only add
optional amber warning flags. High-confidence cells show just the mark, without
a tick. If handwriting is detected but OCR returns no text, `?` remains visible
as an unknown mark rather than silently marking the cell blank.

Teacher review applies to the table as a whole. Click only marks you want to
change: the **Edit Mark** dialog shows the crop and original prediction, and has
Save, Set N/A and Cancel actions. Flags never require acknowledgment or prevent
submission. Unedited predictions remain unchanged on submit. Non-numeric text is
preserved but contributes zero to the existing numeric totals. Reset restores
original predictions/flags. Edits do not mirror between question groups. The
selected group stays fixed for an OCR result. Confidence is not measured accuracy.

## Table layout and limits

The supported rubric has a header, seven rows a–g, a total row, and five columns
(part label plus four questions). The small grand-total extension is excluded.
Use one complete, roughly upright table that fills most of the photograph, with
visible ruled borders. The app's selected Q1–Q4 or Q5–Q8 group determines column
identities; printed question headers are not recognized separately.

OpenCV locates long table edges, computes a perspective transform, then uses
morphological line extraction to find cell boundaries. It requires exactly six
vertical and ten horizontal borders and fails explicitly on unsupported/broken
grids instead of inventing row positions. Automatic extraction handles moderate
perspective; severe rotation, curved pages, missing borders and multiple tables
are outside this baseline. The Python API/CLI also accept four explicit corners
(TL,TR,BR,BL) in the EXIF-oriented source-image coordinate system.

Cells are inset from borders, retain their original-image bounds, and preserve
color/faint strokes. Blank detection estimates paper shading and noise, and checks for connected
stroke-like regions. Clearly blank crops skip OCR; uncertain, dark, or very noisy
crops still go to OCR. The detector does not change the image fed to the model. Validation accepts one or two ASCII digits, an optional
maximum, and never converts letters to guessed digits or blank marks to zero.
The API accepts a `max_mark` for the table; the current Flutter UI does not supply
rubric maxima. The teacher can submit the entire table without editing or acknowledging any flagged cell.

## Scripts and data

Run commands from `obelens-ocr`:

```bash
python -m scripts.test_single_cell path/to/cell.png --max-mark 20
python -m scripts.test_table ../assets/sample_marksheet.png
python -m scripts.evaluate_sample
python -m scripts.test_dataset data/baseline/labels.csv --max-mark 20
```

`test_table` saves the result, rectified table and cell PNGs under `outputs/`.
`evaluate_sample` reproduces the [bundled handwriting report](evaluation/README.md).
Dataset manifests use paths relative to their CSV:

```csv
image_path,label,group
cell_5.png,5,sheet_01
cell_15.png,15,sheet_02
blank.png,,sheet_02
```

Exact-string accuracy preserves leading zeros. Blank references are empty labels,
not zero. Dataset reports contain raw predictions, confusions, review rate,
accepted accuracy and timings including first model initialization. Collect more
writer/sheet-separated labels before interpreting these as deployment accuracy.
Reserved train/val/test/corrections directories remain available for later work.

## API contract

`POST /ocr/table` accepts JSON with `image_base64`, `table_type` (`1-4` or `5-8`),
optional `max_mark`, and optional `corners`. Upload a PNG/JPEG image with a
Content-Length header. Limits are 16 MiB request JSON and 25 megapixels; Flutter
limits original image files to 10 MiB. Responses include `cellMarks`,
`cellResults` (raw text, value, score, review reason, bounds, PNG crop in base64),
`tableCorners`, table confidence and `isVerified=false`.
Malformed images/layouts produce 422, oversized requests 413, token errors 401,
and inference failures 500. Flutter shows scan failures with a retry action.

## Validation

```bash
# From obelens-ocr (requires localhost sockets for the API test)
python -m unittest discover -s tests -v
# From repository root
flutter analyze
flutter test
flutter test test/ocr_service_test.dart --dart-define=OCR_INTEGRATION=true
```

The optional integration test starts a temporary Python server, uploads the
bundled sheet through the actual Dart service and checks the real model response.
Tests cover perspective mapping, broken-grid rejection, crop evidence, API error
handling, byte uploads, response parsing, optional flags, unobstructed submission, edits and blanks.
Previous CRNN code is preserved under `../archive/crnn`; PyTorch was not removed
from any environment.
