"""Verify the running Compose UI, proxy, detection and real OCR with stdlib only.

Usage: python3 docker/smoke_test.py [http://localhost:8080]
"""
import base64
import json
from pathlib import Path
import sys
import urllib.request


def main():
    base = (sys.argv[1] if len(sys.argv) > 1 else 'http://localhost:8080').rstrip('/')
    with urllib.request.urlopen(base + '/', timeout=15) as response:
        assert b'<title>obelens</title>' in response.read(), 'Flutter UI not served'
    with urllib.request.urlopen(base + '/health', timeout=15) as response:
        assert json.load(response)['status'] == 'ok'

    image = Path(__file__).resolve().parents[1] / 'assets/sample_marksheet.png'
    encoded = base64.b64encode(image.read_bytes()).decode('ascii')

    def post(path, **fields):
        request = urllib.request.Request(
            base + path,
            data=json.dumps({'image_base64': encoded, **fields}).encode(),
            headers={'Content-Type': 'application/json'},
        )
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.load(response)

    detection = post('/ocr/detect', rotation=0)
    assert detection['detected'], 'Reference table was not detected'
    result = post('/ocr/table', table_type='5-8', rotation=0,
                  normalized_corners=detection['normalized_corners'])
    assert result['tableType'] == '5-8'
    assert set(result['cellMarks']) == {'5', '6', '7', '8'}
    assert sum(len(parts) for parts in result['cellResults'].values()) == 28
    assert result['cellResults']['5']['a']['crop_base64']
    assert not result['isVerified']
    print('PASS: UI, proxy, detection, and real OCR returned all 28 cells.')


if __name__ == '__main__':
    main()
