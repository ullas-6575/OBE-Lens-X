# OBE Lens

Flutter marks-table capture, four-corner crop/rotation, pretrained handwriting OCR,
and teacher verification.

The [Python OCR service](obelens-ocr/README.md) corrects perspective, extracts the
28 mark cells from the OBE rubric, runs `en_PP-OCRv5_mobile_rec`, and returns
integer marks with crop evidence and confidence flags. Camera and gallery images
first open **Adjust Table**, where automatic detection suggests four corners.
Teachers can drag the corners, rotate in 90° steps, reset, and continue. Detection
failure leaves a manual editor available. Flutter sends the original image plus
normalized corners and rotation; Python straightens the selected table before
reading its 28 cells. Flags are advisory; teachers edit only
the marks they want to change and submit the table in one action.

## Run on a PC with Docker

Install Docker Desktop (Windows/macOS, using Linux containers) or Docker Engine
with the Compose plugin (Linux). From the repository root, run:

```bash
docker compose up --build -d
```

Open **http://localhost:8080**. The existing login → upload → adjust table → OCR
→ verify → save workflow runs in the browser. Uploading a photograph works on
desktop browsers; the camera button uses the browser's file/capture picker and
may offer file selection instead of a live camera on a PC.

The first build downloads Flutter, Python dependencies, and the official
[`en_PP-OCRv5_mobile_rec` model](https://www.paddleocr.ai/main/en/version3.x/module_usage/text_recognition.html).
You do not need Flutter, Python, Android tooling,
or the ignored model directories installed on the host. Subsequent starts reuse
the built images. Allow several minutes and several GB of disk space for the
first build; allocating at least 4 GB RAM to Docker is recommended.

Login and saved results still use the Supabase project in `lib/main.dart` and
require internet access. The existing `public.results` migration below must
already be applied to that project. Docker does not create a replacement
database or change your account data. Scanned images are processed in memory.

The images target **linux/amd64** for the pinned Flutter/Paddle CPU binaries.
Intel/AMD PCs need a [CPU compatible with PaddlePaddle](https://www.paddlepaddle.org.cn/documentation/docs/en/install/pip/linux-pip_en.html)
(including AVX). ARM PCs
and Apple Silicon require Docker's amd64 emulation; that configuration has not
been verified here, and very old CPUs are not supported. Docker makes the
software setup portable, rather than guaranteeing support for every processor.

Useful commands:

```bash
docker compose ps                 # Container status
docker compose logs -f           # Startup or OCR errors
docker compose down              # Stop and remove these containers
docker compose up --build -d     # Rebuild after source changes
```

To change the port, create a root `.env` containing `OBELENS_PORT=8081`, then
run the start command again and open http://localhost:8081. The app is bound to
the local PC by default. Nginx serves Flutter and proxies `/ocr/` to Python,
so no machine-specific IP or CORS configuration is needed. The first recognition
request initializes the model and can take longer than later scans.

For just the OCR API (for an existing native Flutter client):

```bash
docker build --platform linux/amd64 --target ocr -t obelens-ocr .
docker run --rm --init --platform linux/amd64 -p 127.0.0.1:8765:8765 obelens-ocr
```

Check http://localhost:8765/health for the API-only container, or
http://localhost:8080/health for Compose. Health checks confirm the HTTP service
is running; recognition is initialized lazily. To verify a real scan through
Compose, run `python3 docker/smoke_test.py` with any host Python 3 installation
(optional; Python is not needed to run the app).

## Run with local development tools

Start the OCR server from the repository root:

```bash
source .venv/bin/activate
cd obelens-ocr
python -m ocr.server
```

In another terminal, run `flutter run`. Android emulator builds default to
`http://10.0.2.2:8765`; desktop builds default to `http://127.0.0.1:8765`.
For physical devices and HTTPS deployments, see the [connection instructions](obelens-ocr/README.md#flutter-connection).

Email/password login and signup use the Supabase project configured in
`lib/main.dart`. If email confirmation is enabled in Supabase Auth, new users
must confirm their address before signing in.

### Supabase results setup

The verification workflow saves one verified marks grid per row in
`public.results`. Each row stores the roll number, selected table type, marks
grid as JSON, grand total, optional image path, authenticated teacher ID, and
creation time. A single database operation stores the grid atomically, and a
per-verification submission ID makes retries idempotent. Row Level Security
allows signed-in users to insert results under their own account and read only
their own results.

Apply [`supabase/migrations/20261013200000_create_results.sql`](supabase/migrations/20261013200000_create_results.sql)
to the connected Supabase project using the Supabase SQL Editor, then run the
Flutter app. The `results` table and policies must exist before saving or
viewing results. This migration matches the current OCR workflow; it does not
yet define courses, exams, CO/PO mappings, or attainment reports.

The [bundled handwriting evaluation](obelens-ocr/evaluation/README.md) reads 7/8
clearly labeled numeric marks correctly and leaves 17/17 blank cells unresolved.
One sheet is a development check, not a deployment accuracy estimate.

Previous custom CRNN implementations are preserved in [archive/crnn](archive/crnn/README.md).
