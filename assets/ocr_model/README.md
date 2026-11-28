# obelens OCR model

All default OCR paths use `obelens`, the fine-tuned model supplied in
`obelens_stage2_best_accuracy/`, based on `en_PP-OCRv5_mobile_rec`:

- `obelens.onnx` preserves every trained tensor from
  `obelens_stage2_best_accuracy/obelens_stage2_best_accuracy.onnx`, with an
  English-digit output mask added after the final softmax.
- `inference.yml` is the export's PaddleOCR preprocessing and CTC configuration.
- `ppocrv5_en_dict.txt` matches the 436 entries in that configuration, in order.
  The decoder adds the CTC blank and space tokens (438 output classes).

Only ASCII digits `0–9` and the CTC blank can be selected. All other character
probabilities are zeroed without renormalizing the remaining scores, so the
original digit confidence and review threshold are preserved. Keep the full
dictionary: its indices still match the 438-class trained output. This restricts
decoding; it does not retrain the model or guarantee that letters in an image
cannot be misread as digits.

Source ONNX SHA-256: `071fd10c09991e9d08533a107b578d0569772f4ea3fdefe792c8824dd47c76e5`.
Digits-only ONNX SHA-256: `c157749a80b6be1d6697bb9e9be5f54e8e89b8f23919248196753ce2724421cb`.

Android bundles `obelens.onnx` and the dictionary through `pubspec.yaml`. The
Python service keeps its original `obelens-ocr/models/recognition/` directory,
containing an identical copy named `inference.onnx` plus `inference.yml` as
required by PaddleOCR's `onnxruntime` engine. Its model name and `/health` response
are `obelens`; the internal PaddleOCR adapter still uses its architecture name.
Docker copies the bundled model into the image's existing model directory, and
Compose mounts the original service directory read-only. No pretrained weights
are downloaded or used as a fallback.

After replacing model files, update both copies, rebuild/reinstall the Android
app and restart the Python service. Rebuild Docker images to include updated
weights in standalone containers.
