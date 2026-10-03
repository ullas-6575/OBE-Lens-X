"""Shared training/inference preprocessing for extracted cells."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter, ImageOps
import torch
from .config import PreprocessingConfig

ImageInput = str | Path | Image.Image | np.ndarray


def load_image(image: ImageInput, color_order: str = 'BGR') -> Image.Image:
    """Return an independent RGB/L image; uint8 arrays follow OpenCV conventions."""
    if isinstance(image, (str, Path)):
        with Image.open(image) as source:
            return load_image(source, color_order)
    if isinstance(image, np.ndarray):
        if image.dtype != np.uint8:
            raise ValueError('NumPy images must be uint8 in the range 0..255')
        if image.size == 0 or image.ndim not in (2, 3):
            raise ValueError('Expected a nonempty H×W or H×W×C array')
        if image.ndim == 3:
            channels = image.shape[2]
            if channels == 1:
                image = image[:, :, 0]
            elif channels in (3, 4):
                if color_order == 'BGR':
                    image = image[:, :, [2, 1, 0] if channels == 3 else [2, 1, 0, 3]]
            else:
                raise ValueError('Images must have 1, 3, or 4 channels')
        image = Image.fromarray(np.ascontiguousarray(image))
    if not isinstance(image, Image.Image):
        raise TypeError('Image must be a file path, PIL image, or uint8 NumPy array')
    if image.width == 0 or image.height == 0:
        raise ValueError('Image is empty')
    image = ImageOps.exif_transpose(image)
    if image.mode in ('RGBA', 'LA') or 'transparency' in image.info:
        rgba = image.convert('RGBA')
        image = Image.alpha_composite(Image.new('RGBA', rgba.size, 'white'), rgba).convert('RGB')
    return image.copy()


def prepare_image(image: ImageInput, config: PreprocessingConfig = PreprocessingConfig()) -> Image.Image:
    image = load_image(image, config.array_color_order).convert('L')
    if config.median_filter_size:
        image = image.filter(ImageFilter.MedianFilter(config.median_filter_size))
    if config.trim_whitespace:
        # Do not remove grid lines here: this mask only finds foreground bounds.
        mask = image.point(lambda pixel: 255 if pixel < config.whitespace_threshold else 0)
        bounds = mask.getbbox()
        if bounds:
            left, top, right, bottom = bounds
            margin = config.crop_margin
            image = image.crop((max(0, left - margin), max(0, top - margin),
                                min(image.width, right + margin), min(image.height, bottom + margin)))
    if config.threshold is not None:
        image = image.point(lambda pixel: 255 if pixel >= config.threshold else 0)
    scale = min((config.width - 2 * config.padding) / image.width,
                (config.height - 2 * config.padding) / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    image = image.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new('L', (config.width, config.height), 255)
    canvas.paste(image, ((config.width - size[0]) // 2, (config.height - size[1]) // 2))
    return canvas


def preprocess(image: ImageInput, config: PreprocessingConfig = PreprocessingConfig()) -> torch.Tensor:
    canvas = prepare_image(image, config)
    pixels = torch.frombuffer(bytearray(canvas.tobytes()), dtype=torch.uint8).float()
    # White=-1, dark ink=+1. Same convention for training and inference.
    return 1.0 - pixels.reshape(1, config.height, config.width) / 127.5
