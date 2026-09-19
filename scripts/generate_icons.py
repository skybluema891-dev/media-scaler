"""Generate Windows and macOS app icons from the approved square source image."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "705111e2-abe3-48df-9a6f-36714c85b0fa.png"
image = Image.open(SOURCE).convert("RGBA")
side = min(image.size)
left = (image.width - side) // 2
top = (image.height - side) // 2
image = image.crop((left, top, left + side, top + side))

windows = ROOT / "windows/runner/resources/app_icon.ico"
image.save(windows, format="ICO", sizes=[
    (16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)
])

mac = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in (16, 32, 64, 128, 256, 512, 1024):
    resized = image.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(mac / f"app_icon_{size}.png", optimize=True)
