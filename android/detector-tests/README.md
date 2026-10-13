# Android/Linux detection parity

This runner compiles the **production** `TableDetector.kt` and executes its OpenCV
operations on the same PNG pixels used by the Python detector. Synthetic fixtures
have independent expected corners; the generator checks those before exporting
Linux results. Tests compare detection/fallback decisions and corners within four
working-image pixels. Fixtures include broken outer borders, perspective,
missing internal lines, a Grand Total extension, noise/shadows, large camera
images, the bundled reference, and non-table negatives.

From the repository root:

```sh
android/gradlew -p android/detector-tests test
```

The default Python executable is `.venv/bin/python`; override it with
`-Ppython=/absolute/path/to/python` if needed. Images and expected results are
regenerated into `build/detection-fixtures`. HTML test results are in
`android/detector-tests/build/reports/tests/test/index.html`.

The isolated runner uses [OpenPnP's desktop OpenCV JNI package](https://github.com/openpnp/opencv).
It is not an app dependency. These tests execute the real detector core, but do
not test Android camera decoding, device speed, APK installation, or native
library loading on a phone. Run the release APK on target devices for those checks.
