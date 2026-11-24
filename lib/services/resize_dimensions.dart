import 'dart:math';

import '../models/media_item.dart';
import 'app_settings.dart';

// Match FFmpeg scale: multipliers floor to even, -2 rounds to the
// nearest even dimension, and fit rounds both dimensions inside the box.
PixelSize? resizeDimensions(
  PixelSize input,
  ConversionSettings settings, {
  MediaKind kind = MediaKind.image,
}) {
  final (:width, :height) = input;
  if (width < 1 || height < 1) return null;
  final PixelSize output;
  switch (settings.sizeType) {
    case SizeType.multiplier:
      final factor = settings.resizeMultiplier;
      if (!resizeMultipliers.contains(factor)) return null;
      output = (
        width: ((width * factor) / 2).floor() * 2,
        height: ((height * factor) / 2).floor() * 2,
      );
    case SizeType.preset:
      final shortSide = settings.presetHeight;
      if (!sizePresets.contains(shortSide)) return null;
      output = width >= height
          ? (width: _nearestEven(shortSide, width, height), height: shortSide)
          : (width: shortSide, height: _nearestEven(shortSide, height, width));
    case SizeType.custom:
      final frameWidth = settings.customWidth;
      final frameHeight = settings.customHeight;
      if (!validCustomSize(frameWidth, frameHeight)) return null;
      output = (
        width:
            min(frameWidth, _nearestEven(frameHeight, width, height)) ~/ 2 * 2,
        height:
            min(frameHeight, _nearestEven(frameWidth, height, width)) ~/ 2 * 2,
      );
  }
  // Keep the result encodable by the H.265 CPU fallback (libx265).
  final minimum =
      kind == MediaKind.video && settings.videoCodec == VideoCodec.h265
      ? 16
      : 2;
  if (output.width < minimum || output.height < minimum) return null;
  return validCustomSize(output.width, output.height) ? output : null;
}

// FFmpeg's av_rescale rounds positive half ties up. Integer arithmetic avoids
// floating-point discrepancies at a rounding boundary.
int _nearestEven(int side, int numerator, int denominator) =>
    ((side * numerator + denominator) ~/ (2 * denominator)) * 2;

bool validCustomSize(int width, int height) =>
    width >= 2 && height >= 2 && width <= 0x7fffffff && height <= 0x7fffffff;
