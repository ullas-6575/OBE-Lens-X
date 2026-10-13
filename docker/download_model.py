"""Fetch the official model during image build, never on the first user scan."""
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import urllib.request

MODEL_URL = (
    'https://paddle-model-ecology.bj.bcebos.com/paddlex/'
    'official_inference_model/paddle3.0.0/en_PP-OCRv5_mobile_rec_infer.tar'
)
REQUIRED = ('inference.json', 'inference.pdiparams', 'inference.yml')


def download(destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        archive = Path(directory) / 'model.tar'
        with urllib.request.urlopen(MODEL_URL, timeout=120) as response:
            with archive.open('wb') as output:
                shutil.copyfileobj(response, output)
        # Copy only expected regular files; ignore archive paths and symlinks.
        with tarfile.open(archive) as source:
            for name in REQUIRED:
                candidates = [entry for entry in source.getmembers()
                              if entry.isfile() and Path(entry.name).name == name]
                if len(candidates) != 1:
                    raise ValueError(f'Model archive must contain one {name}')
                with source.extractfile(candidates[0]) as stream:
                    (destination / name).write_bytes(stream.read())
    print(f'Model installed at {destination}', flush=True)


if __name__ == '__main__':
    download(sys.argv[1])
