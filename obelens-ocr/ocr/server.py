"""Local OCR JSON API. Run python -m ocr.server --port 8765."""
import argparse
import base64
import io
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from PIL import Image, UnidentifiedImageError
from .config import RecognitionConfig
from .paddle_recognizer import MarkRecognizer
from .full_table import process_table
from .cell_extractor import detect_corners, ExtractionError
from .table_selection import orient_image

MAX_BODY = 16 * 1024 * 1024


def make_handler(recognizer, token=''):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(30)

        def respond(self, status, payload):
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self.respond(200 if self.path == '/health' else 404,
                         {'status': 'ok', 'model': recognizer.config.model_name} if self.path == '/health' else {'error': 'Not found'})

        def do_POST(self):
            if self.path not in ('/ocr/table', '/ocr/detect'):
                self.respond(404, {'error': 'Not found'}); return
            if token and self.headers.get('Authorization') != f'Bearer {token}':
                self.respond(401, {'error': 'Unauthorized'}); return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= MAX_BODY:
                    self.respond(413, {'error': 'Image request is too large or empty'}); return
                request = json.loads(self.rfile.read(length))
                if not isinstance(request, dict):
                    raise ValueError('Expected a JSON object')
                raw = base64.b64decode(request['image_base64'], validate=True)
                with Image.open(io.BytesIO(raw)) as image:
                    if image.width * image.height > 25_000_000:
                        raise ValueError('Image exceeds 25 megapixels')
                    rotation = request.get('rotation', 0)
                    if self.path == '/ocr/detect':
                        source = orient_image(image, rotation)
                        try:
                            payload = {'detected': True, 'normalized_corners': detect_corners(source)}
                        except ExtractionError:
                            payload = {'detected': False, 'normalized_corners': None}
                        payload.update(rotation=rotation, width=source.shape[1], height=source.shape[0])
                    else:
                        payload = process_table(image, recognizer,
                            table_type=request.get('table_type', '1-4'),
                            corners=request.get('corners'), max_mark=request.get('max_mark'),
                            rotation=rotation, normalized_corners=request.get('normalized_corners'))
                self.respond(200, payload)
            except (ValueError, KeyError, TypeError, UnidentifiedImageError, Image.DecompressionBombError) as exc:
                self.respond(422, {'error': str(exc)})
            except Exception:
                self.log_error('OCR inference failed')
                self.respond(500, {'error': 'OCR inference failed; check the server model installation'})
    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--confidence-threshold', type=float, default=.8)
    parser.add_argument('--model-dir', default=str(Path(__file__).resolve().parents[1] / 'models/pretrained/en_PP-OCRv5_mobile_rec'))
    args = parser.parse_args()
    os.environ.setdefault('PADDLE_PDX_CACHE_HOME', str(Path(__file__).resolve().parents[1] / 'models/.paddlex'))
    recognizer = MarkRecognizer(RecognitionConfig(model_dir=args.model_dir, confidence_threshold=args.confidence_threshold))
    server = HTTPServer((args.host, args.port), make_handler(recognizer, os.environ.get('OBELENS_OCR_TOKEN', '')))
    print(f'OCR API listening on http://{args.host}:{server.server_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
