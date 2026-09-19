import 'dart:io';

import 'package:path/path.dart' as p;

enum MediaKind { image, video }

enum JobState { waiting, processing, completed, error, cancelled }

class MediaInfo {
  const MediaInfo({
    this.width,
    this.height,
    this.durationSeconds,
    this.frameRate,
    this.codec,
    this.format,
  });
  final int? width;
  final int? height;
  final double? durationSeconds;
  final double? frameRate;
  final String? codec;
  final String? format;
}

class MediaItem {
  MediaItem(this.path, this.kind) : sizeBytes = File(path).lengthSync();
  final String path;
  final MediaKind kind;
  final int sizeBytes;
  MediaInfo? info;
  JobState state = JobState.waiting;
  double progress = 0;
  Duration elapsed = Duration.zero;
  Duration? remaining;
  String? outputPath;
  String? errorMessage;
  String get fileName => p.basename(path);
}

const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
const videoExtensions = {'.mp4', '.mov', '.mkv', '.avi', '.webm'};

MediaKind? kindFromPath(String path) {
  final extension = p.extension(path).toLowerCase();
  if (imageExtensions.contains(extension)) return MediaKind.image;
  if (videoExtensions.contains(extension)) return MediaKind.video;
  return null;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
