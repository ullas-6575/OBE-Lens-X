"""Explicit teacher corrections, saved for later curated supervised training."""
import csv
from datetime import datetime, timezone
import json
from pathlib import Path
import uuid
from .preprocessing import load_image
from .validation import apply_confidence, validate_mark


def save_correction(image, *, predicted, confidence, corrected,
                    output_dir='data/corrections', max_mark=None, group=None, metadata=None,
                    array_color_order='BGR'):
    validation = validate_mark(corrected, max_mark)
    if not validation['valid']:
        raise ValueError('Teacher correction must be a valid one- or two-digit mark')
    apply_confidence(predicted, confidence, max_mark=max_mark)
    if group is not None and (not isinstance(group, str) or not group):
        raise ValueError('Group must be a nonempty writer/sheet identifier or None')
    # Validate metadata before writing any artifacts.
    json.dumps(metadata or {}, allow_nan=False)
    source = load_image(image, array_color_order)
    root = Path(output_dir)
    root.mkdir(parents=True, exist_ok=True)
    sample_id = uuid.uuid4().hex
    image_path = root / f'{sample_id}.png'
    record = {'id': sample_id, 'image_path': image_path.name, 'predicted': predicted,
              'confidence': float(confidence), 'corrected': corrected, 'max_mark': max_mark,
              'group': group, 'metadata': metadata or {},
              'corrected_at': datetime.now(timezone.utc).isoformat(), 'source': 'teacher_correction'}
    record_path = root / f'{sample_id}.json'
    source.save(image_path, format='PNG')
    record_path.write_text(json.dumps(record, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    return record_path


def export_corrections(record_paths, manifest_path):
    """Explicitly export selected/reviewed correction records to a training CSV."""
    records = []
    manifest_path = Path(manifest_path)
    for path in record_paths:
        path = Path(path)
        record = json.loads(path.read_text(encoding='utf-8'))
        if not validate_mark(record['corrected'], record.get('max_mark'))['valid']:
            raise ValueError(f'Invalid correction: {path}')
        image_path = (path.parent / record['image_path']).resolve()
        if not image_path.is_file():
            raise ValueError(f'Missing corrected crop: {image_path}')
        records.append((str(image_path), record['corrected'], record.get('group') or ''))
    if not records:
        raise ValueError('Select at least one correction record')
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open('w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        writer.writerow(['image_path', 'label', 'group'])
        writer.writerows(records)
    return manifest_path
