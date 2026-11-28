# OBE-Lens OCR

Table photograph → automatic corner suggestion → Flutter crop/rotation preview →
explicit corners → perspective correction → grid extraction → 28 cropped cells →
your supplied local recognition model → advisory integer validation and confidence flags → Flutter review.
The app only runs inference. It has no datasets, training, fine-tuning, or automatic model downloads.

## Setup and server

For a browser UI and OCR service with one command on a PC, use
`docker compose up --build -d` from the repository root and open
http://localhost:8080. See the [Docker setup](../README.md#run-on-a-pc-with-docker)
for requirements, commands, and hardware limits. The fine-tuned
`obelens` model replaces the bundled asset at `assets/ocr_model/obelens.onnx`.
The service keeps an identical copy in `obelens-ocr/models/recognition/`, which
Compose mounts read-only; the standalone image includes it too.
Restart the OCR service after replacing the model.

From the repository root, reuse the existing OCR environment:

```bash
source .venv/bin/activate
pip install -r obelens-ocr/requirements.txt
cd obelens-ocr
python -m ocr.server
```

The verified versions are PaddleOCR 3.7.0, CPU PaddlePaddle 3.3.1,
ONNX Runtime 1.30.0 and OpenCV 4.12. The model directory is `obelens-ocr/models/recognition/`
relative to the repository root. The adapter explicitly selects PaddleOCR's
`onnxruntime` engine and loads `inference.onnx` plus `inference.yml` from the
fine-tuned export. Paddle graph/parameter files are not needed.
Use `python -m ocr.server --model-dir /absolute/path/to/model` for another location.
Missing model files cause an explicit error; the app does not fetch replacement weights.
Android uses the same ONNX bytes as `assets/ocr_model/obelens.onnx` and the
matching dictionary. The service reports the model name `obelens` in `/health`.
The ONNX model allows only English digits (`0–9`) and the CTC blank at its output.
Its fine-tuned weights and digit confidence scores are preserved; other classes
are suppressed after softmax without changing dictionary indices.
See [model provenance](../assets/ocr_model/README.md).

The service defaults to localhost:8765. It uses one reusable recognizer, serves
requests on threads and caps concurrent inference at two so `/health` stays
responsive during a scan. Images and crops are processed in memory; the API
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
  is enabled only in the debug manifest. Browser builds use the same-origin API
  supplied by Docker's Nginx proxy and support image uploads and crop previews.

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
empty cells show `N/A` without warnings. Only one- or two-digit English readings
enter the table, preserving leading zeros. Low-confidence numbers and numbers
above a configured maximum receive an amber warning. The default model emits
only `0–9`; unrecognized handwriting and readings longer than two digits display
`N/A` with a warning. Raw OCR predictions remain available in the edit dialog and
API cell details. Restricting output does not guarantee that letters in an image
cannot be misread as digits; original confidence scores still drive review flags.
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

Detection follows resize → grayscale → Gaussian blur → adaptive threshold →
morphological closing → contours → large convex quadrilaterals → candidate
scoring → perspective warp → row/column validation. Geometry scoring uses
area, rectangularity, and the expected portrait aspect ratio; warped grid
alignment selects the marks table instead of a larger page border. Android
runs this locally using the [official OpenCV Android package](https://opencv.org/opencv4android-usage-models/),
without loading the OCR model. Both paths apply EXIF orientation before user rotation.
Both Android and Python recover partial outer edges through the same
line/template fitting when no contour passes validation. The main rubric is perspective-warped to a
fixed 1000 × 1400 area, then the 28 marks
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

Android and the Python backend used by Linux, macOS, Windows, and iOS follow
these same detection settings (a reachable Python API is required outside Android):

| Stage | Shared behavior |
| --- | --- |
| Resize | Long edge at most 2000 pixels, OpenCV linear interpolation |
| Threshold | BGR → gray, 5×5 Gaussian blur, Gaussian adaptive threshold, block 31, C=12, inverted |
| Morphology | 5×5 closing, then up to 80 largest contours |
| Candidates | Convex quadrilaterals, at least 1000 pixels and 2% of image area; contour tolerances .015/.025/.04 |
| Ranking | Rectangularity, area, and portrait aspect ratio; warped grid score selects the winner |
| Warp/check | Unblurred source → 1000×1400 area with 8-pixel margin → gray/blur/threshold |
| Accept | At least 3 vertical and 4 horizontal template-border matches within 3.5% |
| Recovery | Same Hough line grouping/template fitting, then the same warped-grid check |
| Fallback | Keep manual corner editing available when no candidate passes |

Android decoding keeps at least 2000 pixels on the long edge when the photo is
large enough, avoiding the old power-of-two undersampling. EXIF orientation
precedes user rotation. Debug and release builds use the same detector.
The [cross-platform regression runner](../android/detector-tests/README.md)
executes the actual Kotlin core against Python results; device speed and camera
integration still require testing on a phone.

Cells are inset from borders, retain bounds in the oriented/rotated source frame, and preserve
color/faint strokes. Blank detection estimates paper shading and noise, and checks for connected
stroke-like regions. Clearly blank crops skip OCR; uncertain, dark, or very noisy
crops still go to OCR. The detector does not change the image fed to the model. Validation accepts one or two ASCII digits, an optional
maximum, and never converts letters to guessed digits or blank marks to zero.
The API accepts a `max_mark` for the table; the current Flutter UI does not supply
rubric maxima. The teacher can submit the entire table without editing or acknowledging any flagged cell.

## Try your model on an image

Run commands from `obelens-ocr`:

```bash
python -m scripts.test_single_cell path/to/cell.png --max-mark 20
python -m scripts.test_table path/to/your-table.png
```

Both commands use `models/recognition/` by default and accept `--model-dir`.
`test_table` saves JSON, a rectified table and cell PNGs under `outputs/` for
manual inspection. The API processes uploads in memory and does not save crops.

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
generated synthetic sheet through detection and manual-selection OCR using the actual Dart
service, and checks the real model response.
Tests cover perspective mapping, broken-grid rejection, crop evidence, API error
handling, byte uploads, response parsing, optional flags, unobstructed submission, edits and blanks.
PaddleOCR 3.7.0 supports Pillow 13, which this service requires for its image
decoder security fixes.
