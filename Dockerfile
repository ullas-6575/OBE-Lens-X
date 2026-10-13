# syntax=docker/dockerfile:1

# CPU OCR runtime. No host Python environment or pre-downloaded model is needed.
FROM python:3.12-slim-bookworm AS ocr
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True \
    PADDLE_PDX_CACHE_HOME=/tmp/paddlex \
    OMP_NUM_THREADS=2
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY obelens-ocr/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY docker/download_model.py /tmp/download_model.py
RUN python /tmp/download_model.py /app/models/pretrained/en_PP-OCRv5_mobile_rec
COPY obelens-ocr/ocr ./ocr
RUN useradd --create-home --uid 10001 obelens
USER obelens
EXPOSE 8765
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=6 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/health', timeout=4).read()"
CMD ["python", "-m", "ocr.server", "--host", "0.0.0.0", "--port", "8765"]

# Build the existing Flutter UI for a browser, retaining the same screen flow.
FROM debian:bookworm-slim AS flutter-build
ARG FLUTTER_VERSION=3.24.0
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils libglu1-mesa && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}
RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics --enable-web \
    && flutter precache --web
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile
COPY lib ./lib
COPY web ./web
COPY assets ./assets
RUN flutter build web --release --no-pub --pwa-strategy=none

# Optional browser diagnostic build; never included in the normal web image.
FROM flutter-build AS browser-check
COPY docker/browser_smoke.dart ./browser_smoke.dart
RUN flutter build web --release --no-pub --pwa-strategy=none \
    --target browser_smoke.dart --base-href /browser-check/

# Same-origin proxy means no CORS configuration or host-specific API URL.
FROM nginx:1.28-alpine AS web
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=flutter-build /app/build/web /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/
