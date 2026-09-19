import 'app_settings.dart';

/// Keep the source stem when renaming is disabled. Callers still avoid collisions.
String outputStem(String sourceStem, AppSettings settings, {bool ai = false}) {
  if (!settings.renameOutput) return sourceStem;
  final size = switch (settings.sizeType) {
    SizeType.multiplier => '${settings.multiplier}x',
    SizeType.preset => '${settings.presetHeight}p',
    SizeType.custom => '${settings.customWidth}x${settings.customHeight}',
  };
  final prefix = ai
      ? 'ai_'
      : settings.sizeType == SizeType.multiplier
      ? '${settings.scaleMode == ScaleMode.upscale ? 'upscale' : 'downscale'}_'
      : '';
  return '${sourceStem}_$prefix$size';
}
