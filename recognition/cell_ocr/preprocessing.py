from PIL import Image, ImageOps
import torch

HEIGHT, WIDTH = 32, 96


def preprocess(image: Image.Image) -> torch.Tensor:
    """Preserve aspect ratio; center on white; normalize dark ink to +1."""
    image = ImageOps.exif_transpose(image)
    if image.mode in ("RGBA", "LA") or "transparency" in image.info:
        rgba = image.convert("RGBA")
        background = Image.new("RGBA", rgba.size, "white")
        image = Image.alpha_composite(background, rgba)
    image = image.convert("L")
    scale = min((WIDTH - 4) / image.width, (HEIGHT - 4) / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    image = image.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("L", (WIDTH, HEIGHT), 255)
    canvas.paste(image, ((WIDTH - size[0]) // 2, (HEIGHT - size[1]) // 2))
    pixels = torch.frombuffer(bytearray(canvas.tobytes()), dtype=torch.uint8).float()
    return (1.0 - pixels.reshape(1, HEIGHT, WIDTH) / 127.5)
