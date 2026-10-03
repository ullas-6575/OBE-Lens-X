# Bundled handwriting development evaluation

Source: `assets/sample_marksheet.png`. Eight clearly readable numeric cells were
visually transcribed before running predictions; references and exclusions are
in `sample_reference.json`. The writer/source provenance is unknown. This is one
development sheet, not an independent handwriting benchmark or held-out test set.

The full-table extractor produced all 28 cells. With the unmodified pretrained
`en_PP-OCRv5_mobile_rec` and confidence threshold 0.8:

| Measurement | Result |
| --- | --- |
| Numeric exact-string accuracy | 7 / 8 (87.5%) |
| Numeric integer-value accuracy | 7 / 8 (87.5%) |
| Clearly blank cells detected, displayed as N/A | 17 / 17 |
| Numeric hallucinations on blanks | 0 |
| Cells with optional warning flags | 5 / 28 |
| Cells excluded from numeric accuracy | 3 |

The failed numeric cell is Q4(c): reference `07`, prediction `o7`. Integer
validation flags it, while the table displays the raw `o7` prediction so the
teacher may optionally edit it. The flag never blocks submission. Q4(a) has an ambiguous
digit; Q4(b) is a slash and Q3(d) a dash. They are excluded explicitly, not assigned
guessed numeric labels. The conservative paper/noise detector now classifies all 17 labeled blank cells
as empty before OCR, so they display `N/A` without flags. This development-sample
result does not guarantee performance on other paper textures or fainter writing.

Run `python -m scripts.evaluate_sample` from `obelens-ocr` to reproduce
`sample_report.json` and crop images in `outputs/cells/sample`. The report records
every raw prediction and confidence, including excluded cells. Timing includes
model initialization and is not a pure inference benchmark.

Use additional teacher-labeled sheets from different writers, including complete
mark ranges and difficult captures, for a defensible accuracy estimate. No model
weights or recognition thresholds were tuned on this sample.
