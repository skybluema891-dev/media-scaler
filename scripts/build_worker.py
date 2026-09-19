"""Package AI runtime. Windows uses PSF-signed embedded Python (no frozen EXE)."""
from pathlib import Path
import os
import subprocess
import sys
import shutil
import zipfile
import importlib.metadata as metadata
from prepare_tools import download

root = Path(__file__).resolve().parents[1]
os_name = "windows" if os.name == "nt" else "macos"
target = root/"tools/ai"/os_name
if os.name == "nt":
    archive = download("https://www.python.org/ftp/python/3.13.15/python-3.13.15-embed-amd64.zip",
                       root/"tools/downloads/python-embed.zip")
    runtime = target/"python"
    runtime.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as package:
        package.extractall(runtime)
    subprocess.run([sys.executable, "-m", "pip", "install", "--upgrade", "--no-deps",
        "--target", str(runtime/"Lib/site-packages"),
        "ncnn==1.0.20260526", "numpy==2.5.3", "Pillow==12.3.0"], check=True)
    (runtime/"python313._pth").write_text("python313.zip\n.\nLib/site-packages\n", encoding="utf-8")
    shutil.copy2(root/"ai_worker/worker.py", target/"worker.py")
else:
    subprocess.run([sys.executable, "-m", "PyInstaller", "--noconfirm", "--onedir",
        "--name", "media_ai", "--collect-all", "ncnn", "--distpath", str(target),
        "--workpath", str(root/"build/ai-freeze"), "--specpath", str(root/"build"),
        str(root/"ai_worker/worker.py")], check=True)
licenses = root/"tools/licenses/python-packages"
licenses.mkdir(parents=True, exist_ok=True)
for dist in metadata.distributions():
    name = dist.metadata.get("Name", "unknown")
    for entry in dist.files or []:
        if "license" in str(entry).lower() or "copying" in str(entry).lower():
            source = Path(dist.locate_file(entry))
            if source.is_file() and source.stat().st_size < 2_000_000:
                (licenses/(name+"-"+source.name)).write_bytes(source.read_bytes())

