import 'app_settings.dart';

/// Keep the source stem when renaming is disabled. Callers still avoid collisions.
String outputStem(
  String sourceStem,
  ConversionSettings settings, {
  bool ai = false,
}) {
  if (!settings.renameOutput) return sourceStem;
  final size = switch (settings.sizeType) {
    SizeType.multiplier =>
      '${ai ? settings.aiMultiplier : formatMultiplier(settings.resizeMultiplier)}x',
    SizeType.preset => '${settings.presetHeight}p',
    SizeType.custom => '${settings.customWidth}x${settings.customHeight}',
  };
  final prefix = ai
      ? 'ai_'
      : settings.sizeType == SizeType.multiplier
      ? 'resize_'
      : '';
  return '${sourceStem}_$prefix$size';
}
