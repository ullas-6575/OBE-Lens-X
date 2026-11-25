FROM --platform=linux/amd64 debian:bookworm-slim AS flutter-build

ARG FLUTTER_VERSION=3.24.0
# Official sha256 from releases_linux.json; the tarball is verified before extraction.
ARG FLUTTER_SHA256=d52a5d12f17d8bcf868d1ccc01fe0f7ffb05b53d9628aa21b07a18f9d33621f2
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
WORKDIR /app

# The Flutter archive stores uid 1000. Extracted as root it would be owned by a
# different user, so git reports "dubious ownership", Flutter then reports version
# 0.0.0-unknown and `pub get` rejects every plugin. Extract with our ownership and
# whitelist the SDK for git's safe.directory check.
RUN apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl git tar xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/flutter.tar.xz "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar --no-same-owner -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --system --add safe.directory /opt/flutter

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
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --home-dir /app app \
    && rm -rf /var/lib/apt/lists/*
COPY obelens-ocr/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY obelens-ocr/ocr ./ocr
COPY --from=model /model ./models/pretrained/en_PP-OCRv5_mobile_rec

# The model cache under /app/models is written at runtime, so hand ownership over.
RUN chown -R app:app /app
USER app

EXPOSE 8765
CMD ["python", "-m", "ocr.server", "--host", "0.0.0.0", "--port", "8765", "--model-dir", "/app/models/pretrained/en_PP-OCRv5_mobile_rec"]

FROM --platform=linux/amd64 nginx:stable-alpine AS web
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=flutter-build /app/build/web /usr/share/nginx/html
EXPOSE 80
