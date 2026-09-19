"""Fetch pinned official Real-ESRGAN package; no user media is uploaded."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OS = "windows" if os.name == "nt" else "macos"
AI_TAG = "v0.2.5.0"
AI_NAME = "realesrgan-ncnn-vulkan-20220424-" + OS + ".zip"


def download(url, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        request = urllib.request.Request(url, headers={"User-Agent": "MediaScaler-build"})
        with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as out:
            shutil.copyfileobj(response, out)
    return destination


def main():
    archive = download("https://github.com/xinntao/Real-ESRGAN/releases/download/" + AI_TAG + "/" + AI_NAME,
                       ROOT / "tools/downloads" / AI_NAME)
    target = ROOT / "tools/ai" / OS
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            # Allow only model, engine, runtime and upstream documentation files.
            name = Path(member.filename)
            if name.is_absolute() or ".." in name.parts:
                raise ValueError("Unsafe archive path")
            if ("models" in name.parts or name.name.startswith("realesrgan-ncnn-vulkan")
                    or name.suffix in (".dll", ".dylib", ".md", ".txt")):
                package.extract(member, target)
    if OS == "macos":
        for engine in target.rglob("realesrgan-ncnn-vulkan"):
            engine.chmod(0o755)
        # Official macOS archive may have a containing directory.
    engines = list(target.rglob("realesrgan-ncnn-vulkan" + (".exe" if OS == "windows" else "")))
    engine = next(e for e in engines if e.is_file())
    if engine.parent != target:
        for child in engine.parent.iterdir():
            dest = target / child.name
            if child.is_dir():
                shutil.copytree(child, dest, dirs_exist_ok=True)
            else:
                shutil.copy2(child, dest)
    licenses = ROOT / "tools/licenses"
    download("https://raw.githubusercontent.com/xinntao/Real-ESRGAN/master/LICENSE", licenses / "Real-ESRGAN.txt")
    download("https://raw.githubusercontent.com/Tencent/ncnn/master/LICENSE.txt", licenses / "ncnn.txt")
    provenance = {"ai_url": "https://github.com/xinntao/Real-ESRGAN/releases/download/" + AI_TAG + "/" + AI_NAME,
                  "ai_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                  "platform": platform.platform()}
    if OS == "windows":
        base = "ffmpeg-n8.1-latest-win64-gpl-8.1"
        ffzip = download("https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/" + base + ".zip",
                         ROOT / "tools/downloads" / (base + ".zip"))
        ffdir = ROOT / "tools/ffmpeg/windows"
        ffdir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(ffzip) as package:
            for name in ("ffmpeg.exe", "ffprobe.exe"):
                with package.open(base + "/bin/" + name) as src, (ffdir / name).open("wb") as dst:
                    shutil.copyfileobj(src, dst)
            (ffdir / "FFMPEG-LICENSE.txt").write_bytes(package.read(base + "/LICENSE.txt"))
        provenance["ffmpeg_sha256"] = hashlib.sha256(ffzip.read_bytes()).hexdigest()
        provenance["ffmpeg_source"] = "https://github.com/BtbN/FFmpeg-Builds"
    (target / "PROVENANCE.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

