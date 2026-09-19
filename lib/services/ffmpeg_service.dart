import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../models/media_item.dart';
import 'app_logger.dart';
import 'app_settings.dart';

typedef ProgressCallback = void Function(
  double progress,
  Duration elapsed,
  Duration? remaining,
);

class FfmpegMissingException implements Exception {
  const FfmpegMissingException();
  @override
  String toString() => 'FFmpegが見つかりません。FFmpeg導入ガイド.txtに従って配置してください。';
}

class ConversionException implements Exception {
  const ConversionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class FfmpegService {
  Process? _process;
  bool _cancelRequested = false;
  String? _ffmpegPath;
  String? _ffprobePath;
  Set<String>? _encoders;
  final Map<String, bool> _encoderUsability = {};

  bool get isRunning => _process != null;
  Future<String> get ffmpegPath async {
    if (_ffmpegPath == null) await initialize();
    return _ffmpegPath!;
  }

  Future<String> get ffprobePath async {
    if (_ffprobePath == null) await initialize();
    return _ffprobePath!;
  }

  Future<void> initialize() async {
    _ffmpegPath = await _findExecutable('ffmpeg');
    _ffprobePath = await _findExecutable('ffprobe');
    if (_ffmpegPath == null || _ffprobePath == null) {
      throw const FfmpegMissingException();
    }
    await AppLogger.write('FFmpeg: $_ffmpegPath');
  }

  Future<String?> _findExecutable(String name) async {
    final suffix = Platform.isWindows ? '.exe' : '';
    final osFolder = Platform.isWindows ? 'windows' : 'macos';
    final executableDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      if (Platform.isMacOS)
        p.join(
          p.dirname(executableDir),
          'Resources',
          'tools',
          'ffmpeg',
          osFolder,
          '$name$suffix',
        ),
      p.join(executableDir, 'tools', 'ffmpeg', osFolder, '$name$suffix'),
      p.join(
        executableDir,
        'data',
        'flutter_assets',
        'tools',
        'ffmpeg',
        osFolder,
        '$name$suffix',
      ),
      p.join(
        Directory.current.path,
        'tools',
        'ffmpeg',
        osFolder,
        '$name$suffix',
      ),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        name,
      ]);
      if (result.exitCode == 0) {
        final first = result.stdout
            .toString()
            .split(RegExp(r'[\r\n]+'))
            .first
            .trim();
        if (first.isNotEmpty) return first;
      }
    } catch (_) {}
    return null;
  }

  Future<MediaInfo> probe(String path) async {
    if (_ffprobePath == null) await initialize();
    final result = await Process.run(_ffprobePath!, [
      '-v',
      'error',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      path,
    ]);
    if (result.exitCode != 0) {
      throw const ConversionException(
        'ファイル情報を読み取れませんでした。ファイルが破損していないか確認してください。',
      );
    }
    final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final streams = (data['streams'] as List<dynamic>? ?? const []);
    final video = streams
        .cast<Map<String, dynamic>>()
        .where((stream) => stream['codec_type'] == 'video')
        .firstOrNull;
    final format = data['format'] as Map<String, dynamic>?;
    return MediaInfo(
      width: _asInt(video?['width']),
      height: _asInt(video?['height']),
      durationSeconds: _asDouble(video?['duration'] ?? format?['duration']),
      frameRate: _parseRate(video?['avg_frame_rate']),
      codec: video?['codec_name']?.toString(),
      format:
          format?['format_long_name']?.toString() ??
          format?['format_name']?.toString(),
    );
  }

  int? _asInt(Object? value) =>
      value == null ? null : int.tryParse(value.toString());
  double? _asDouble(Object? value) =>
      value == null ? null : double.tryParse(value.toString());
  double? _parseRate(Object? value) {
    final parts = value?.toString().split('/');
    if (parts == null || parts.length != 2) return _asDouble(value);
    final numerator = double.tryParse(parts[0]);
    final denominator = double.tryParse(parts[1]);
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    return numerator / denominator;
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    final process = _process;
    if (process == null) return;
    process.stdin.write('q');
    await process.stdin.flush();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_process != null) {
      process.kill(
        Platform.isWindows ? ProcessSignal.sigterm : ProcessSignal.sigint,
      );
    }
  }

  Future<String> convert({
    required MediaItem item,
    required AppSettings settings,
    required ProgressCallback onProgress,
  }) async {
    if (_ffmpegPath == null) await initialize();
    _cancelRequested = false;
    final outputPath = await _createOutputPath(item, settings);
    final duration = item.info?.durationSeconds ?? 0;
    final stopwatch = Stopwatch()..start();
    final filter = _scaleFilter(settings);
    final encoder = item.kind == MediaKind.video
        ? await _selectEncoder(settings)
        : null;
    final cpuEncoder = item.kind == MediaKind.video
        ? await _selectCpuEncoder(settings.videoCodec)
        : null;
    final args = _arguments(item, outputPath, settings, filter, encoder);
    try {
      if (encoder != null) {
        await AppLogger.write('使用エンコーダー: $encoder');
      }
      final exitCode = await _run(args, duration, stopwatch, onProgress);
      if (_cancelRequested) {
        await _removePartial(outputPath);
        throw const ConversionException('キャンセルしました。');
      }
      if (exitCode != 0 && encoder != null && encoder != cpuEncoder) {
        await AppLogger.write('GPUエンコード失敗。CPUへ切替: $encoder');
        await _removePartial(outputPath);
        final retryArgs = _arguments(
          item,
          outputPath,
          settings,
          filter,
          cpuEncoder,
        );
        final retryCode = await _run(
          retryArgs,
          duration,
          stopwatch,
          onProgress,
        );
        if (_cancelRequested) throw const ConversionException('キャンセルしました。');
        if (retryCode != 0) {
          throw const ConversionException('変換に失敗しました。詳細はログを確認してください。');
        }
      } else if (exitCode != 0) {
        throw const ConversionException('変換に失敗しました。形式や保存先を確認し、詳細はログを確認してください。');
      }
      onProgress(1, stopwatch.elapsed, Duration.zero);
      return outputPath;
    } catch (_) {
      await _removePartial(outputPath);
      rethrow;
    } finally {
      stopwatch.stop();
      _process = null;
    }
  }

  Future<int> _run(
    List<String> args,
    double duration,
    Stopwatch stopwatch,
    ProgressCallback onProgress,
  ) async {
    await AppLogger.write('実行: ${args.join(' ')}');
    final process = await Process.start(_ffmpegPath!, args);
    _process = process;
    final errors = StringBuffer();
    final stderrSubscription = process.stderr.transform(utf8.decoder).listen((
      text,
    ) {
      if (errors.length < 12000) errors.write(text);
    });
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!line.startsWith('out_time_')) return;
          double? seconds;
          if (line.startsWith('out_time_us=')) {
            seconds = double.tryParse(line.substring('out_time_us='.length));
            if (seconds != null) seconds /= 1000000;
          } else if (line.startsWith('out_time_ms=')) {
            seconds = double.tryParse(line.substring('out_time_ms='.length));
            if (seconds != null) seconds /= 1000000;
          }
          if (seconds == null || duration <= 0) return;
          final progress = min(seconds / duration, 0.99);
          final remaining = progress > 0.01
              ? Duration(
                  milliseconds:
                      (stopwatch.elapsedMilliseconds *
                              (1 - progress) /
                              progress)
                          .round(),
                )
              : null;
          onProgress(progress, stopwatch.elapsed, remaining);
        });
    final code = await process.exitCode;
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
    if (code != 0) await AppLogger.write('FFmpeg終了コード $code\n$errors');
    _process = null;
    return code;
  }

  List<String> _arguments(
    MediaItem item,
    String output,
    AppSettings settings,
    String filter,
    String? encoder,
  ) {
    final args = ['-hide_banner', '-y', '-i', item.path, '-vf', filter];
    if (item.kind == MediaKind.image) {
      final extension = p.extension(output).toLowerCase();
      if (extension == '.jpg' || extension == '.jpeg') {
        final q = (31 - settings.jpegQuality * 29 / 100).round().clamp(2, 31);
        args.addAll(['-q:v', '$q']);
      } else if (extension == '.png') {
        args.addAll(['-compression_level', '6']);
      }
      args.addAll(['-frames:v', '1']);
    } else {
      if (encoder == null) {
        throw const ConversionException('選択した動画形式に対応するエンコーダーがありません。');
      }
      args.addAll(['-c:v', encoder]);
      args.addAll(_videoQualityArgs(settings, encoder));
      args.addAll(['-c:a', 'aac', '-b:a', '192k']);
      if (p.extension(output).toLowerCase() == '.mp4' ||
          p.extension(output).toLowerCase() == '.mov') {
        args.addAll(['-movflags', '+faststart']);
      }
    }
    args.addAll(['-progress', 'pipe:1', '-nostats', output]);
    return args;
  }

  String _scaleFilter(AppSettings settings) {
    final flags = switch (settings.normalQuality) {
      NormalQuality.fast => 'bilinear',
      NormalQuality.standard => 'bicubic',
      NormalQuality.high => 'lanczos',
    };
    if (settings.sizeType == SizeType.multiplier) {
      return 'scale=trunc(iw*${settings.multiplier}/2)*2:trunc(ih*${settings.multiplier}/2)*2:flags=$flags';
    }
    if (settings.sizeType == SizeType.preset) {
      final size = settings.presetHeight;
      return 'scale=if(gte(iw\\,ih)\\,-2\\,$size):if(gte(iw\\,ih)\\,$size\\,-2):flags=$flags';
    }
    return 'scale=${settings.customWidth}:${settings.customHeight}:force_original_aspect_ratio=decrease:force_divisible_by=2:flags=$flags';
  }

  Future<String> _selectEncoder(AppSettings settings) async {
    _encoders ??= await _readEncoders();
    if (settings.useGpu) {
      final candidates = settings.videoCodec == VideoCodec.h264
          ? (Platform.isMacOS
                ? ['h264_videotoolbox']
                : ['h264_nvenc', 'h264_amf', 'h264_qsv'])
          : (Platform.isMacOS
                ? ['hevc_videotoolbox']
                : ['hevc_nvenc', 'hevc_amf', 'hevc_qsv']);
      for (final candidate in candidates.where(_encoders!.contains)) {
        if (await _canUseEncoder(candidate)) return candidate;
      }
    }
    return _selectCpuEncoder(settings.videoCodec);
  }

  Future<Set<String>> _readEncoders() async {
    final result = await Process.run(_ffmpegPath!, [
      '-hide_banner',
      '-encoders',
    ]);
    final text = '${result.stdout}\n${result.stderr}';
    return RegExp(
      r'^\s*[A-Z\.]{6}\s+(\S+)',
      multiLine: true,
    ).allMatches(text).map((match) => match.group(1)!).toSet();
  }

  Future<bool> _canUseEncoder(String encoder) async {
    final cached = _encoderUsability[encoder];
    if (cached != null) return cached;
    try {
      final process = await Process.start(_ffmpegPath!, [
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'color=c=black:s=64x64:d=0.1',
        '-frames:v',
        '1',
        '-an',
        '-c:v',
        encoder,
        '-f',
        'null',
        Platform.isWindows ? 'NUL' : '/dev/null',
      ]);
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final stdoutFuture = process.stdout.drain<void>();
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(const Duration(seconds: 6));
      } on TimeoutException {
        process.kill();
        exitCode = -1;
      }
      await stdoutFuture;
      final errorText = await stderrFuture;
      final usable = exitCode == 0;
      _encoderUsability[encoder] = usable;
      await AppLogger.write(
        usable
            ? 'GPUエンコーダー利用可能: $encoder'
            : 'GPUエンコーダー利用不可: $encoder ${errorText.trim()}',
      );
      return usable;
    } catch (error) {
      _encoderUsability[encoder] = false;
      await AppLogger.write('GPUエンコーダー確認失敗: $encoder $error');
      return false;
    }
  }

  Future<String> _selectCpuEncoder(VideoCodec codec) async {
    _encoders ??= await _readEncoders();
    final candidates = codec == VideoCodec.h264
        ? ['libx264', 'libopenh264', 'h264_mf']
        : ['libx265', 'libkvazaar', 'hevc_mf'];
    final encoder = candidates.where(_encoders!.contains).firstOrNull;
    if (encoder == null) {
      throw const ConversionException('選択した動画形式をCPUで変換できません。');
    }
    return encoder;
  }

  List<String> _videoQualityArgs(AppSettings settings, String encoder) {
    final crf = switch (settings.videoQuality) {
      VideoQuality.compact => 28,
      VideoQuality.standard => 23,
      VideoQuality.high => 19,
      VideoQuality.maximum => 16,
    };
    if (encoder.contains('videotoolbox')) {
      return ['-realtime', 'true', '-q:v', '${max(20, 70 - crf * 2)}'];
    }
    if (encoder.contains('nvenc')) {
      final preset = switch (settings.normalQuality) {
        NormalQuality.fast => 'p1',
        NormalQuality.standard => 'p3',
        NormalQuality.high => 'p5',
      };
      return ['-preset', preset, '-tune', 'hq', '-cq', '$crf', '-b:v', '0'];
    }
    if (encoder.contains('_amf')) {
      final quality = switch (settings.normalQuality) {
        NormalQuality.fast => 'speed',
        NormalQuality.standard => 'balanced',
        NormalQuality.high => 'quality',
      };
      return [
        '-quality',
        quality,
        '-rc',
        'cqp',
        '-qp_i',
        '$crf',
        '-qp_p',
        '$crf',
      ];
    }
    if (encoder.contains('_qsv')) {
      final preset = switch (settings.normalQuality) {
        NormalQuality.fast => 'veryfast',
        NormalQuality.standard => 'faster',
        NormalQuality.high => 'medium',
      };
      return ['-preset', preset, '-global_quality', '$crf'];
    }
    if (encoder == 'libopenh264' ||
        encoder == 'libkvazaar' ||
        encoder.endsWith('_mf')) {
      final bitrate = switch (settings.videoQuality) {
        VideoQuality.compact => '2M',
        VideoQuality.standard => '4M',
        VideoQuality.high => '8M',
        VideoQuality.maximum => '12M',
      };
      return ['-b:v', bitrate];
    }
    return [
      '-crf',
      '$crf',
      '-preset',
      switch (settings.normalQuality) {
        NormalQuality.fast => 'ultrafast',
        NormalQuality.standard => 'veryfast',
        NormalQuality.high => 'medium',
      },
      '-threads',
      '0',
    ];
  }

  Future<String> _createOutputPath(MediaItem item, AppSettings settings) async {
    final directory = settings.sameFolder
        ? p.dirname(item.path)
        : settings.outputDirectory;
    if (directory.isEmpty) throw const ConversionException('保存先フォルダを選択してください。');
    await Directory(directory).create(recursive: true);
    final extension = item.kind == MediaKind.video
        ? '.mp4'
        : p.extension(item.path);
    final stem = p.basenameWithoutExtension(item.path);
    final suffix = settings.sizeType == SizeType.multiplier
        ? '${settings.scaleMode == ScaleMode.upscale ? 'upscale' : 'downscale'}_${settings.multiplier}x'
        : settings.sizeType == SizeType.preset
        ? '${settings.presetHeight}p'
        : '${settings.customWidth}x${settings.customHeight}';
    var candidate = p.join(directory, '${stem}_$suffix$extension');
    var number = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(directory, '${stem}_${suffix}_$number$extension');
      number++;
    }
    return candidate;
  }

  Future<void> _removePartial(String path) async {
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        await file.rename('$path.未完了');
      }
    }
  }
}
