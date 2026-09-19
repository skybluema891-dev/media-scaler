"""Real executable regression tests; generated media only, no user files."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
TOOLS_ROOT = Path(os.environ.get("MEDIA_SCALER_TEST_APP", str(ROOT)))
OS = "windows" if os.name == "nt" else "macos"
SUFFIX = ".exe" if os.name == "nt" else ""
ENGINE = ([str(TOOLS_ROOT / "tools/ai/windows/python/python.exe"),
           str(TOOLS_ROOT / "tools/ai/windows/worker.py")] if os.name == "nt" else
          [str(TOOLS_ROOT / "tools/ai/macos/media_ai/media_ai")])
def ffmpeg_tool(name):
    bundled = TOOLS_ROOT / "tools/ffmpeg" / OS / (name + SUFFIX)
    if os.name == "nt" or "MEDIA_SCALER_TEST_APP" in os.environ:
        return str(bundled)
    return shutil.which(name)


FF = ffmpeg_tool("ffmpeg")
FP = ffmpeg_tool("ffprobe")


class WorkerTests(unittest.TestCase):
    def setUp(self):
        (ROOT/"validation").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=ROOT/"validation", prefix="ai-test-")
        self.addCleanup(self.temp.cleanup)
        self.dir = Path(self.temp.name)

    def convert(self, src, dst, kind="image", extra=()):
        cmd = [*ENGINE, "--input", str(src), "--output", str(dst), "--kind", kind,
               "--models", str(TOOLS_ROOT/"tools/ai"/OS/"models"), "--ffmpeg", FF, "--ffprobe", FP,
               "--quality", "fast", "--scale", "2", *extra]
        return subprocess.run(cmd, capture_output=True, timeout=120)

    def image(self):
        src = self.dir/"日本語 input.png"
        a = np.zeros((24, 32, 4), dtype=np.uint8)
        a[:, :, 0] = np.arange(32) * 8
        a[:, :, 1] = np.arange(24)[:,None] * 10
        a[:,:,3] = 180
        Image.fromarray(a).save(src)
        return src

    def test_cpu_real_inference_alpha_and_no_overwrite(self):
        src, dst = self.image(), self.dir/"result.png"
        result = self.convert(src, dst)
        self.assertEqual(result.returncode, 0, result.stderr)
        with Image.open(dst) as image:
            self.assertEqual(image.size, (64,48))
            self.assertEqual(image.mode, "RGBA")
            self.assertGreater(np.asarray(image)[:,:,:3].std(), 10)
        before = dst.read_bytes()
        retry = self.convert(src, dst)
        self.assertNotEqual(retry.returncode, 0)
        self.assertEqual(before, dst.read_bytes())

    def test_missing_model_fails(self):
        src, dst = self.image(), self.dir/"missing.png"
        result = self.convert(src, dst, extra=("--models", str(self.dir/"none")))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(dst.exists())

    def test_photo_high_custom_size(self):
        dst = self.dir/"photo.png"
        result = self.convert(self.image(), dst, extra=("--quality", "high",
            "--model", "photo", "--size", "custom", "--width", "80", "--height", "60"))
        self.assertEqual(result.returncode, 0, result.stderr)
        with Image.open(dst) as image:
            self.assertEqual(image.size, (80, 60))

    def test_preview_creates_comparison(self):
        dst, original = self.dir/"preview.png", self.dir/"original.png"
        result = self.convert(self.image(), dst, extra=("--preview",
            "--preview-original", str(original)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(original.is_file())
        self.assertTrue(dst.is_file())

    def test_video_audio_dimensions_and_duration(self):
        src, dst = self.dir/"in.mp4", self.dir/"out.mp4"
        subprocess.run([FF,"-v","error","-f","lavfi","-i","testsrc=size=32x24:rate=2:duration=1",
            "-f","lavfi","-i","sine=frequency=440:duration=1","-c:v","libx264",
            "-pix_fmt","yuv420p","-c:a","aac","-shortest",str(src)], check=True, capture_output=True)
        result = self.convert(src, dst, kind="video")
        self.assertEqual(result.returncode, 0, result.stderr)
        info = json.loads(subprocess.check_output([FP,"-v","error","-show_streams","-of","json",str(dst)]))
        video = next(s for s in info["streams"] if s["codec_type"]=="video")
        self.assertEqual((video["width"],video["height"]),(64,48))
        self.assertAlmostEqual(float(video["duration"]),1.0,places=1)
        self.assertTrue(any(s["codec_type"]=="audio" for s in info["streams"]))


if __name__ == "__main__":
    unittest.main()
