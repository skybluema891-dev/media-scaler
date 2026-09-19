"""Offline Real-ESRGAN worker. JSON lines on stdout; diagnostics on stderr."""
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from fractions import Fraction

import numpy as np
from PIL import Image, ImageOps
import ncnn

FLAGS = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
START = time.monotonic()


def emit(**data):
    print(json.dumps(data, ensure_ascii=True), flush=True)


def run(args, **kwargs):
    return subprocess.run(args, check=True, creationflags=FLAGS, **kwargs)


def dimensions(w, h, args, video=False):
    if args.size == "multiplier":
        ow, oh = w * args.scale, h * args.scale
    elif args.size == "preset":
        ratio = args.height / min(w, h)
        ow, oh = round(w * ratio), round(h * ratio)
    else:
        ratio = min(args.width / w, args.height / h)
        ow, oh = round(w * ratio), round(h * ratio)
    if video:
        ow, oh = max(2, ow // 2 * 2), max(2, oh // 2 * 2)
    if ow * oh > 100_000_000 or max(ow, oh) > 32768:
        raise ValueError("仕上がりサイズが大きすぎます。倍率・解像度を小さくしてください。")
    return max(1, ow), max(1, oh)


class Engine:
    def __init__(self, args, temp):
        self.args, self.temp = args, Path(temp)
        self.net = None
        self.gpu = args.gpu
        self.model = ("realesr-animevideov3" if args.quality == "fast"
                      else "realesrgan-x4plus-anime" if args.model == "anime"
                      else "realesrgan-x4plus")
        self.native_scale = args.scale if self.model == "realesr-animevideov3" else 4
        self.stem = (self.model + "-x" + str(self.native_scale)
                     if self.model == "realesr-animevideov3" else self.model)
        model_path = Path(args.models)
        for ext in (".bin", ".param"):
            if not (model_path / (self.stem + ext)).is_file():
                raise ValueError("AIモデルがありません。アプリを再インストールしてください。")
        self.binary = model_path.parent / ("realesrgan-ncnn-vulkan.exe" if os.name == "nt"
                                          else "realesrgan-ncnn-vulkan")
        self.device_reported = False

    def cpu(self, image):
        if self.net is None:
            self.net = ncnn.Net()
            self.net.opt.use_vulkan_compute = False
            self.net.opt.num_threads = max(1, min(os.cpu_count() or 2, 8))
            # Unicode-safe model loading: param as text, weights through byte memory.
            param = (Path(self.args.models) / (self.stem + ".param")).read_text()
            if self.net.load_param_mem(param) != 0:
                raise ValueError("AIモデルの読み込みに失敗しました。")
            # ncnn Python load_model uses UTF-8 paths on supported wheels.
            if self.net.load_model(str(Path(self.args.models) / (self.stem + ".bin"))) != 0:
                raise ValueError("AIモデルの重みを読み込めません。")
        arr = np.asarray(image.convert("RGB"))
        h, w, _ = arr.shape
        scale, tile, pad = self.native_scale, 64, 16
        output = np.empty((h * scale, w * scale, 3), dtype=np.uint8)
        total = math.ceil(w / tile) * math.ceil(h / tile)
        done = 0
        for y in range(0, h, tile):
            for x in range(0, w, tile):
                x0, y0 = max(0, x-pad), max(0, y-pad)
                x1, y1 = min(w, x+tile+pad), min(h, y+tile+pad)
                rgb = np.ascontiguousarray(arr[y0:y1, x0:x1])
                mat = ncnn.Mat.from_pixels(rgb, ncnn.Mat.PixelType.PIXEL_RGB, x1-x0, y1-y0)
                mat.substract_mean_normalize([], [1/255.0]*3)
                with self.net.create_extractor() as ex:
                    ex.input("data", mat)
                    ret, result = ex.extract("output")
                    if ret != 0:
                        raise ValueError("CPUでのAI処理に失敗しました。")
                    pixels = np.array(result).transpose(1, 2, 0)
                    pixels = np.clip(pixels * 255, 0, 255).round().astype(np.uint8)
                tw, th = min(tile, w-x), min(tile, h-y)
                ox, oy = (x-x0)*scale, (y-y0)*scale
                output[y*scale:(y+th)*scale, x*scale:(x+tw)*scale] = pixels[oy:oy+th*scale, ox:ox+tw*scale]
                done += 1
                if self.args.kind == "image":
                    emit(progress=0.05 + 0.85*done/total, stage="AI処理中（CPU）")
        return Image.fromarray(output)

    def enhance(self, image):
        alpha = image.getchannel("A") if image.mode == "RGBA" else None
        rgb = image.convert("RGB")
        enhanced = None
        if self.gpu and self.binary.exists():
            src, dst = self.temp / "input.png", self.temp / "output.png"
            rgb.save(src)
            dst.unlink(missing_ok=True)
            cmd = [str(self.binary), "-i", str(src), "-o", str(dst),
                   "-m", self.args.models, "-n", self.model,
                   "-s", str(self.native_scale), "-t", "128", "-j", "1:1:1"]
            if self.args.quality == "high" and self.args.kind == "image":
                cmd.append("-x")
            try:
                result = subprocess.run(cmd, capture_output=True, timeout=300, creationflags=FLAGS)
                if result.returncode or not dst.exists():
                    raise RuntimeError(result.stderr.decode("utf-8", errors="replace")[-1500:])
                with Image.open(dst) as im:
                    enhanced = im.convert("RGB")
                if not self.device_reported:
                    emit(device="GPU（Vulkan / Metal）", stage="AI処理中")
                    self.device_reported = True
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                print(str(error), file=sys.stderr)
                self.gpu = False
                emit(device="CPU", stage="GPUを利用できないためCPUへ切り替え")
        if enhanced is None:
            if not self.device_reported:
                emit(device="CPU", stage="AI処理中")
                self.device_reported = True
            enhanced = self.cpu(rgb)
            if self.args.quality == "high" and self.args.kind == "image":
                # Mirror ensemble reduces direction-dependent artifacts.
                reflected = ImageOps.mirror(self.cpu(ImageOps.mirror(rgb)))
                enhanced = Image.blend(enhanced, reflected, 0.5)
        if alpha is not None:
            enhanced.putalpha(alpha.resize(enhanced.size, Image.Resampling.LANCZOS))
        return enhanced

    def enhance_batch(self, images):
        """Enhance a video batch with one GPU startup instead of one per frame."""
        if not images:
            return []
        if not self.gpu or not self.binary.exists():
            return [self.enhance(image) for image in images]
        batch = self.temp / "gpu_batch"
        inputs, outputs = batch / "input", batch / "output"
        inputs.mkdir(parents=True, exist_ok=True)
        outputs.mkdir(parents=True, exist_ok=True)
        for old in (*inputs.glob("*.png"), *outputs.glob("*.png")):
            old.unlink()
        for index, image in enumerate(images):
            image.convert("RGB").save(inputs / f"{index:05d}.png", compress_level=1)
        cmd = [str(self.binary), "-i", str(inputs), "-o", str(outputs),
               "-m", self.args.models, "-n", self.model,
               "-s", str(self.native_scale), "-t", "128", "-j", "2:2:2", "-f", "png"]
        # TTA (-x) multiplies video processing time dramatically. High quality
        # video still uses the selected x4 model; TTA is reserved for images.
        try:
            result = subprocess.run(cmd, capture_output=True, timeout=1800, creationflags=FLAGS)
            expected = [outputs / f"{index:05d}.png" for index in range(len(images))]
            if result.returncode or not all(path.exists() for path in expected):
                raise RuntimeError(result.stderr.decode("utf-8", errors="replace")[-2000:])
            enhanced = []
            for path in expected:
                with Image.open(path) as image:
                    enhanced.append(image.convert("RGB"))
            if not self.device_reported:
                emit(device="GPU（Vulkan / Metal）", stage="AI動画をGPUでまとめて処理中")
                self.device_reported = True
            return enhanced
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            print(str(error), file=sys.stderr, flush=True)
            self.gpu = False
            emit(device="CPU", stage="GPU処理に失敗したためCPUへ切り替え")
            return [self.enhance(image) for image in images]


def image_job(args, engine):
    with Image.open(args.input) as im:
        image = ImageOps.exif_transpose(im).copy()
    size = dimensions(*image.size, args)
    if args.preview:
        image.thumbnail((256, 256))
        size = (image.width * args.scale, image.height * args.scale)
        image.save(args.preview_original)
    result = engine.enhance(image).resize(size, Image.Resampling.LANCZOS)
    if Path(args.output).suffix.lower() in (".jpg", ".jpeg"):
        result.convert("RGB").save(args.output, quality=args.jpeg_quality)
    else:
        result.save(args.output)


def video_job(args, engine, temp):
    data = json.loads(run([args.ffprobe, "-v", "error", "-show_streams", "-show_format",
                           "-of", "json", args.input], capture_output=True).stdout)
    stream = next(s for s in data["streams"] if s["codec_type"] == "video")
    if stream.get("color_transfer") in ("smpte2084", "arib-std-b67"):
        raise ValueError("HDR動画のAI変換は未対応です。SDRへ変換してから追加してください。")
    w, h = stream["width"], stream["height"]
    # FFmpeg autorotation is disabled; apply known display rotation consistently.
    rotation = next((int(s.get("rotation", 0)) for s in stream.get("side_data_list", [])
                     if "rotation" in s), 0)
    fps = Fraction(stream.get("avg_frame_rate", "0/1"))
    if fps <= 0:
        fps = Fraction(stream.get("r_frame_rate", "30/1"))
    if fps <= 0 or fps > 240:
        raise ValueError("この動画のフレームレートには対応していません。")
    output_fps = fps if args.max_fps == 0 else min(fps, Fraction(args.max_fps, 1))
    duration = float(data.get("format", {}).get("duration", 0))
    iw, ih = (h, w) if abs(rotation) % 180 == 90 else (w, h)
    ow, oh = dimensions(iw, ih, args, video=True)
    crf = {"compact": 28, "standard": 23, "high": 19, "maximum": 16}[args.video_quality]
    raw_output = str(Path(temp) / "silent.mp4")
    decoder = encoder = None
    # File-backed stderr avoids deadlock on lengthy diagnostics.
    with open(Path(temp) / "decode.log", "w+b") as dec_log, open(Path(temp) / "encode.log", "w+b") as enc_log:
        try:
            decoder = subprocess.Popen([args.ffmpeg, "-v", "error", "-noautorotate",
                "-i", args.input, "-map", "0:v:0", "-vf", "fps=" + str(output_fps),
                "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
                stdout=subprocess.PIPE, stderr=dec_log, creationflags=FLAGS)
            encoder = subprocess.Popen([args.ffmpeg, "-v", "error", "-n", "-f", "rawvideo",
                "-pix_fmt", "rgb24", "-s", f"{ow}x{oh}", "-r", str(output_fps), "-i", "pipe:0",
                "-c:v", "libx264" if args.codec == "h264" else "libx265",
                "-preset", "veryfast", "-crf", str(crf), "-pix_fmt", "yuv420p", raw_output],
                stdin=subprocess.PIPE, stderr=enc_log, creationflags=FLAGS)
            frame_bytes, count = w*h*3, 0
            # Limit decoded/output memory while amortizing model startup.
            batch_size = max(2, min(12, 16_000_000 // max(1, w*h)))
            frames = []
            def write_batch():
                nonlocal count
                if not frames:
                    return
                results = engine.enhance_batch(frames)
                for result in results:
                    encoder.stdin.write(result.resize((ow, oh), Image.Resampling.LANCZOS).tobytes())
                    count += 1
                    progress = min(.94, .94 * count / max(1, duration * float(output_fps)))
                    emit(progress=progress,
                         stage=f"AI動画処理中：{count}フレーム（{float(output_fps):g} fps）")
                frames.clear()
            while True:
                buf = bytearray()
                while len(buf) < frame_bytes:
                    part = decoder.stdout.read(frame_bytes-len(buf))
                    if not part:
                        break
                    buf.extend(part)
                if not buf:
                    break
                if len(buf) != frame_bytes:
                    raise ValueError("動画フレームが途中で切れています。")
                image = Image.frombytes("RGB", (w,h), bytes(buf))
                if rotation:
                    image = image.rotate(rotation, expand=True)
                frames.append(image)
                if len(frames) >= batch_size:
                    write_batch()
            write_batch()
            encoder.stdin.close()
            encoder.stdin = None
            if decoder.wait() != 0 or encoder.wait() != 0 or count == 0:
                raise ValueError("動画の読み込みまたは書き出しに失敗しました。")
            emit(progress=.96, stage="音声を結合中")
            run([args.ffmpeg, "-v", "error", "-n", "-i", raw_output, "-i", args.input,
                 "-map", "0:v:0", "-map", "1:a:0?", "-c:v", "copy", "-c:a", "aac",
                 "-b:a", "192k", "-map_metadata", "1", "-metadata:s:v:0", "rotate=0",
                 "-movflags", "+faststart", args.output], capture_output=True)
        finally:
            for process in (decoder, encoder):
                if process and process.poll() is None:
                    process.kill()
                    process.wait()


def main():
    if os.name != "nt":
        os.setsid()
    parser = argparse.ArgumentParser()
    for key in ("input", "output", "models", "ffmpeg", "ffprobe"):
        parser.add_argument("--"+key, required=True)
    parser.add_argument("--kind", choices=["image","video"], required=True)
    parser.add_argument("--model", choices=["photo","anime"], default="photo")
    parser.add_argument("--quality", choices=["fast","standard","high"], default="standard")
    parser.add_argument("--scale", type=int, choices=[2,3,4], default=2)
    parser.add_argument("--size", choices=["multiplier","preset","custom"], default="multiplier")
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    parser.add_argument("--codec", choices=["h264","h265"], default="h264")
    parser.add_argument("--video-quality", choices=["compact","standard","high","maximum"], default="standard")
    parser.add_argument("--jpeg-quality", type=int, default=90)
    parser.add_argument("--max-fps", type=int, choices=[0,24,30], default=30)
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--preview-original", default="")
    args = parser.parse_args()
    if Path(args.output).exists():
        raise ValueError("出力ファイルが既に存在します。")
    emit(progress=0, stage="AIモデルを準備中")
    # App supplies an owned output staging directory. All temp files stay under it.
    with tempfile.TemporaryDirectory(prefix="ai-work-", dir=Path(args.output).parent) as temp:
        engine = Engine(args, temp)
        if args.kind == "image":
            image_job(args, engine)
        else:
            video_job(args, engine, temp)
    emit(progress=1, stage="完了", elapsed=time.monotonic()-START)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(repr(error), file=sys.stderr)
        emit(error=str(error) if isinstance(error, ValueError) else
             "AI処理に失敗しました。保存先の空き容量とモデルを確認してください。詳細はログに記録しました。")
        sys.exit(1)
