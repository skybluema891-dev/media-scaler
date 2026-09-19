import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import 'app_settings.dart';
import 'app_logger.dart';
import 'ffmpeg_service.dart';
import 'output_name.dart';

class AiService {
  Process? _process;
  bool _cancelled = false;
  bool _running = false;

  static String get os => Platform.isWindows ? 'windows' : 'macos';

  static Future<Directory> installation() async {
    final executableDir = p.dirname(Platform.resolvedExecutable);
    for (final toolsRoot in [
      if (Platform.isMacOS)
        p.join(p.dirname(executableDir), 'Resources', 'tools'),
      p.join(executableDir, 'tools'),
      p.join(Directory.current.path, 'tools'),
    ]) {
      final dir = Directory(p.join(toolsRoot, 'ai', os));
      final exe = p.join(
        dir.path,
        Platform.isWindows ? 'python' : 'media_ai',
        Platform.isWindows ? 'python.exe' : 'media_ai',
      );
      if (await File(exe).exists()) return dir;
    }
    throw const ConversionException('AIエンジンがありません。Phase 3対応版を再インストールしてください。');
  }

  Future<String> modelStatus() async {
    try {
      final dir = await installation();
      var bytes = 0;
      await for (final file in Directory(p.join(dir.path, 'models')).list()) {
        if (file is File) bytes += await file.length();
      }
      return 'モデル準備済み（${formatBytes(bytes)}）・オフラインで利用可能';
    } catch (_) {
      return 'AIエンジン未準備：Phase 3対応版のインストールが必要です';
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    final process = _process;
    if (process == null) return;
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    } else {
      // Worker runs in its own process group (setsid), including FFmpeg children.
      await Process.run('/bin/kill', ['-TERM', '-${process.pid}']);
      process.kill();
    }
    await process.exitCode;
  }

  Future<String> convert({
    required MediaItem item,
    required AppSettings settings,
    required FfmpegService ffmpeg,
    required ProgressCallback onProgress,
    void Function(String)? onStage,
    bool preview = false,
    String? previewDirectory,
  }) async {
    if (_running) throw const ConversionException('AI処理が既に実行中です。');
    _running = true;
    _cancelled = false;
    Directory? stage;
    final watch = Stopwatch()..start();
    Timer? ticker;
    double progress = 0;
    void report() {
      final left = progress > .01
          ? Duration(
              milliseconds:
                  (watch.elapsedMilliseconds * (1 - progress) / progress)
                      .round(),
            )
          : null;
      onProgress(progress, watch.elapsed, left);
    }

    try {
      final install = await installation();
      final destination = preview
          ? previewDirectory!
          : settings.sameFolder
          ? p.dirname(item.path)
          : settings.outputDirectory;
      if (destination.isEmpty) throw const ConversionException('保存先を選択してください。');
      await Directory(destination).create(recursive: true);
      stage = await Directory(destination).createTemp('.media-ai-');
      final extension = preview
          ? '.png'
          : item.kind == MediaKind.video
          ? '.mp4'
          : p.extension(item.path);
      final output = p.join(stage.path, 'result$extension');
      final args = [
        if (Platform.isWindows) p.join(install.path, 'worker.py'),
        '--input',
        p.absolute(item.path),
        '--output',
        p.absolute(output),
        '--models',
        p.absolute(p.join(install.path, 'models')),
        '--ffmpeg',
        await ffmpeg.ffmpegPath,
        '--ffprobe',
        await ffmpeg.ffprobePath,
        '--kind',
        item.kind.name,
        '--quality',
        settings.aiQuality.name,
        '--model',
        settings.aiModel,
        '--scale',
        '${settings.multiplier}',
        '--size',
        settings.sizeType.name,
        '--width',
        '${settings.customWidth}',
        '--height',
        '${settings.sizeType == SizeType.preset ? settings.presetHeight : settings.customHeight}',
        '--codec',
        settings.videoCodec.name,
        '--video-quality',
        settings.videoQuality.name,
        '--jpeg-quality',
        '${settings.jpegQuality}',
        '--max-fps',
        '${settings.aiVideoFps}',
        if (settings.aiUseGpu) '--gpu',
        if (preview) ...[
          '--preview',
          '--preview-original',
          p.join(previewDirectory!, 'original.png'),
        ],
      ];
      if (_cancelled) throw const ConversionException('キャンセルしました。');
      final exe = p.join(
        install.path,
        Platform.isWindows ? 'python' : 'media_ai',
        Platform.isWindows ? 'python.exe' : 'media_ai',
      );
      final process = await Process.start(exe, args);
      _process = process;
      if (_cancelled) await cancel();
      ticker = Timer.periodic(const Duration(seconds: 1), (_) => report());
      String? error;
      final errors = StringBuffer();
      final stderrDone = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach((text) {
            if (errors.length < 16000) errors.write(text);
          });
      final stdoutDone = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .forEach((line) {
            try {
              final event = jsonDecode(line) as Map<String, dynamic>;
              if (event['progress'] is num) {
                progress = (event['progress'] as num).toDouble().clamp(0, 1);
              }
              if (event['stage'] is String) {
                onStage?.call(event['stage'] as String);
              }
              if (event['error'] is String) error = event['error'] as String;
              report();
            } catch (_) {}
          });
      final code = await process.exitCode;
      await Future.wait([stderrDone, stdoutDone]);
      _process = null;
      await AppLogger.write(
        'AI終了コード $code / ${settings.aiModel} / ${settings.aiQuality.name}\n$errors',
      );
      if (_cancelled) throw const ConversionException('キャンセルしました。');
      if (code != 0 || !await File(output).exists()) {
        throw ConversionException(error ?? 'AI処理に失敗しました。ログを確認してください。');
      }
      // Atomic reservation prevents overwriting pre-existing outputs, including races.
      final stem = preview
          ? 'preview'
          : outputStem(
              p.basenameWithoutExtension(item.path),
              settings,
              ai: true,
            );
      String target;
      var index = 0;
      while (true) {
        target = p.join(
          destination,
          '$stem${index == 0 ? '' : '_$index'}$extension',
        );
        try {
          await File(target).create(exclusive: true);
          break;
        } on FileSystemException {
          if (!await File(target).exists()) rethrow;
          index++;
        }
      }
      try {
        await File(output).copy(target);
      } catch (_) {
        await File(target).delete();
        rethrow;
      }
      progress = 1;
      report();
      return target;
    } on FileSystemException {
      throw const ConversionException('保存先へ書き込めません。空き容量とアクセス権を確認してください。');
    } finally {
      ticker?.cancel();
      if (_process != null) await cancel();
      _process = null;
      if (stage != null && await stage.exists()) {
        try {
          await stage.delete(recursive: true);
        } catch (_) {}
      }
      _running = false;
      watch.stop();
    }
  }

  static Future<Directory> previewFolder() async {
    final support = await getApplicationSupportDirectory();
    final previews = Directory(p.join(support.path, 'previews'));
    await previews.create(recursive: true);
    return previews.createTemp('comparison-');
  }
}
