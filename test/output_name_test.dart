import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_scaler/services/app_settings.dart';
import 'package:media_scaler/services/output_name.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default keeps existing normal and AI filenames', () async {
    final settings = await AppSettings.load();
    expect(settings.renameOutput, isTrue);
    expect(outputStem('動画', settings), '動画_upscale_2x');
    expect(outputStem('画像', settings, ai: true), '画像_ai_2x');
    settings.sizeType = SizeType.preset;
    expect(outputStem('動画', settings), '動画_1080p');
    expect(outputStem('動画', settings, ai: true), '動画_ai_1080p');
    settings.sizeType = SizeType.custom;
    expect(outputStem('画像', settings), '画像_1920x1080');
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
        expect(outputStem('旅行.movie', restored), '旅行.movie');
        expect(outputStem('旅行.movie', restored, ai: true), '旅行.movie');
      }
    }
  });
}
