FROM --platform=linux/amd64 debian:bookworm-slim AS flutter-build

ARG FLUTTER_VERSION=3.47.5
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
WORKDIR /app

RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl git tar xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      | tar -xJ -C /opt

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

FROM --platform=linux/amd64 python:3.11-slim-bookworm AS model
WORKDIR /build
COPY docker/download_model.py ./download_model.py
RUN python download_model.py /model

FROM --platform=linux/amd64 python:3.11-slim-bookworm AS ocr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PADDLE_PDX_CACHE_HOME=/app/models/.paddlex
WORKDIR /app

RUN apt-get update \
    && apt-get install --no-install-recommends -y libgl1 libglib2.0-0 libgomp1 \
    && rm -rf /var/lib/apt/lists/*
COPY obelens-ocr/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY obelens-ocr/ocr ./ocr
COPY --from=model /model ./models/pretrained/en_PP-OCRv5_mobile_rec

EXPOSE 8765
CMD ["python", "-m", "ocr.server", "--host", "0.0.0.0", "--port", "8765", "--model-dir", "/app/models/pretrained/en_PP-OCRv5_mobile_rec"]

FROM --platform=linux/amd64 nginx:stable-alpine AS web
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=flutter-build /app/build/web /usr/share/nginx/html
EXPOSE 80
