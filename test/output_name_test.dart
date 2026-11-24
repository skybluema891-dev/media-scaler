import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_scaler/services/app_settings.dart';
import 'package:media_scaler/services/output_name.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('normal and AI filenames use their own multiplier', () async {
    final settings = await AppSettings.load();
    expect(settings.renameOutput, isTrue);
    expect(outputStem('動画', settings.conversion), '動画_resize_2x');
    settings.resizeMultiplier = 0.5;
    settings.aiMultiplier = 3;
    expect(outputStem('動画', settings.conversion), '動画_resize_0.5x');
    expect(outputStem('画像', settings.conversion, ai: true), '画像_ai_3x');
    settings.sizeType = SizeType.preset;
    settings.presetHeight = 480;
    expect(outputStem('動画', settings.conversion), '動画_480p');
    expect(outputStem('動画', settings.conversion, ai: true), '動画_ai_480p');
    settings.sizeType = SizeType.custom;
    expect(outputStem('画像', settings.conversion), '画像_1920x1080');
  });

  test('rename disabled preserves stem for every mode and persists', () async {
    final settings = await AppSettings.load();
    settings.renameOutput = false;
    await settings.save();
    final restored = await AppSettings.load();
    expect(restored.renameOutput, isFalse);
    for (final size in SizeType.values) {
      for (final mode in ScaleMode.values) {
        restored.sizeType = size;
        restored.scaleMode = mode;
        expect(outputStem('旅行.movie', restored.conversion), '旅行.movie');
        expect(
          outputStem('旅行.movie', restored.conversion, ai: true),
          '旅行.movie',
        );
      }
    }
  });
}
