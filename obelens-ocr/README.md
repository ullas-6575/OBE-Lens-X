# OBE Lens OCR

Table photograph → automatic corner suggestion → Flutter crop/rotation preview →
explicit corners → perspective correction → grid extraction → 28 cropped cells →
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

The app first calls `POST /ocr/detect` for a corner suggestion, without running
the recognizer. **Continue** then uploads to `POST /ocr/table` for recognition.

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

The **Adjust Table** screen always opens after camera/gallery selection. It shows
four draggable corners and dims the area outside them. Automatic detection
prepositions the corners when possible; if it fails or the service is unavailable,
the teacher can still adjust them manually. Rotate Left/Right applies 90° turns;
Reset restores the last successful automatic selection (or the initial frame).
Auto-detect can be retried after rotation. Include the header, all seven part rows,
and the total row; exclude the small Grand Total extension. Dragging is optional
when the detected selection is correct. Arrow keys also move focused handles.
Late detection responses never replace a selection the user has already changed.
An OCR failure offers **Adjust Table Corners**, preserving the selection.

The complete reconstructed table is ready immediately after scanning. Clearly
empty cells show `N/A` without warnings. Only one- or two-digit numeric readings
enter the table, preserving leading zeros. Low-confidence numbers and numbers
above a configured maximum receive an amber warning. Letters, mixed text such
as `o7`, symbols, and unrecognized handwriting display `N/A` with a warning;
their raw OCR text remains available in the edit dialog and API cell details.
Letters are never guessed or removed to manufacture a numeric mark.
High-confidence valid numbers show just the mark, without a tick.

Teacher review applies to the table as a whole. Click only marks you want to
change: the **Edit Mark** dialog shows the crop and original prediction, and has
Save, Set N/A and Cancel actions. Flags never require acknowledgment or prevent
submission. Submission contains only numeric marks or `N/A`, which contributes
zero to totals. Reset restores the numeric/N/A display and original flags.
Edits do not mirror between question groups. The
selected group stays fixed for an OCR result. Confidence is not measured accuracy.

## Table layout and limits

The supported rubric has a header, seven rows a–g, a total row, and five columns
(part label plus four questions). The small grand-total extension is excluded.
Use one complete, roughly upright table that fills most of the photograph, with
visible ruled borders. The app's selected Q1–Q4 or Q5–Q8 group determines column
identities; printed question headers are not recognized separately.

OpenCV registers detected full or partial lines against normalized OBE layouts,
with connected quadrilateral contours as a localization fallback. Short edges
of the Grand Total extension are excluded from the main-grid geometry. The
main rubric is perspective-warped to a fixed 1000 × 1400 area, then the 28 marks
are cropped using normalized reference coordinates. Visible internal lines can
refine those coordinates; missing or extra lines are not fatal. Both question
groups use the same geometry and retain their selected question identities.

Automatic localization needs aggregate grid evidence (at least three vertical and four
horizontal template positions), rather than every outer/internal border. A
missing outer edge can be estimated from the remaining lines. If no candidate
has enough alignment evidence, the preview offers manual corner adjustment.
Explicit corners skip localization and allow template-based extraction even
without enough visible borders; visible lines still refine the chosen layout.
With no usable internal lines the reference OBE template is assumed, so check the
result carefully. Arbitrary layouts and curved pages remain unsupported. Rotate
sideways photographs upright in the preview; moderate perspective is supported.
The existing API/CLI pixel `corners` format remains available.

Cells are inset from borders, retain bounds in the oriented/rotated source frame, and preserve
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

`POST /ocr/detect` accepts `image_base64` and optional `rotation`. It returns
`detected`, `normalized_corners` (or null), `rotation`, and oriented/rotated
`width`/`height`. A valid photograph with no detected table returns 200 with
`detected=false`; it does not load the recognition model. Both endpoints use the
same upload limits and optional bearer token.

`POST /ocr/table` accepts JSON with `image_base64`, `table_type` (`1-4` or `5-8`),
optional `max_mark`, optional `rotation`, and either `normalized_corners` or the
existing pixel-coordinate `corners` (never both). Omitting corners retains
automatic extraction. Rotation is 0, 90, 180, or 270 degrees clockwise and is
applied to pixels **after EXIF orientation**, before interpreting corners.
Normalized coordinates are four `[x,y]` pairs in **TL, TR, BR, BL** order, relative
to that rotated image, with `x_pixel = x * (width - 1)` and
`y_pixel = y * (height - 1)`. They must form a convex upright quadrilateral and
lie between 0 and 1. Flutter sends the unchanged original image, not screen
coordinates or a recompressed crop. Returned `tableCorners` and cell `bounds`
refer to the EXIF-oriented, user-rotated source image.

```json
{
  "image_base64": "...",
  "table_type": "5-8",
  "rotation": 90,
  "normalized_corners": [[0.1,0.1],[0.9,0.12],[0.88,0.9],[0.12,0.88]]
}
```

Upload a PNG/JPEG image with a
Content-Length header. Limits are 16 MiB request JSON and 25 megapixels; Flutter
limits original image files to 10 MiB. Responses include `cellMarks`,
`cellResults` (raw text, value, score, review reason, bounds, PNG crop in base64),
`tableCorners`, table confidence and `isVerified=false`.
Malformed images/layouts produce 422, oversized requests 413, token errors 401,
and inference failures 500. Flutter shows scan failures with retry and corner-adjustment actions.

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
bundled sheet through detection and manual-selection OCR using the actual Dart
service, and checks the real model response.
Tests cover perspective mapping, broken-grid rejection, crop evidence, API error
handling, byte uploads, response parsing, optional flags, unobstructed submission, edits and blanks.
Previous CRNN code is preserved under `../archive/crnn`; PyTorch was not removed
from any environment.
