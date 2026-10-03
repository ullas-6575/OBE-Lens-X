# OCR datasets

Reserved directories: `train/`, `val/`, `test/`, and `corrections/`.

No handwriting samples are bundled. Place extracted crops in the relevant directory and create a `labels.csv` with `image_path,label` and optional `group` columns. Paths resolve relative to that CSV. Keep writers/sheets separate across splits. See [the OCR data contract](../ocr/README.md#data-contract).

Teacher corrections are explicitly saved as paired PNG/JSON records. Curate and export selected records before using them for offline supervised training. Sample files and correction records are ignored by Git.
