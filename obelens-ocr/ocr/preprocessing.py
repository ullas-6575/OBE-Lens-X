"""Conservative cell loading; Paddle handles model resizing/normalization."""
from pathlib import Path
from typing import Union
import numpy as np
from PIL import Image, ImageOps

ImageInput = Union[str, Path, Image.Image, np.ndarray]


def prepare_cell(image: ImageInput) -> np.ndarray:
    """Return uint8 BGR. NumPy inputs follow OpenCV BGR/BGRA conventions.

    Preserve faint strokes, aspect ratio and whitespace for the first baseline.
    Crops must already exclude grid borders. No thresholding or tensor scaling.
    """
    if isinstance(image, (str, Path)):
        with Image.open(image) as source:
            return prepare_cell(ImageOps.exif_transpose(source).copy())
    if isinstance(image, np.ndarray):
        if image.dtype != np.uint8 or image.size == 0:
            raise ValueError('Cell arrays must be nonempty uint8 images')
        if image.ndim == 2:
            image = Image.fromarray(image)
        elif image.ndim == 3 and image.shape[2] in (3, 4):
            order = [2, 1, 0, 3] if image.shape[2] == 4 else [2, 1, 0]
            image = Image.fromarray(image[:, :, order])
        else:
            raise ValueError('Expected grayscale, BGR or BGRA cell array')
    if not isinstance(image, Image.Image):
        raise TypeError('Expected a path, PIL image or NumPy cell array')
    rgba = ImageOps.exif_transpose(image).convert('RGBA')
    background = Image.new('RGBA', rgba.size, 'white')
    rgb = Image.alpha_composite(background, rgba).convert('RGB')
    return np.ascontiguousarray(np.asarray(rgb)[:, :, ::-1])
