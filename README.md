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
