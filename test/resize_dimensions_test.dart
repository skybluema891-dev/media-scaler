import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_scaler/models/media_item.dart';
import 'package:media_scaler/services/app_settings.dart';
import 'package:media_scaler/services/resize_dimensions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('480p applies to the short side of the entire batch', () async {
    final settings = await AppSettings.load()
      ..sizeType = SizeType.preset
      ..presetHeight = 480;
    PixelSize? result(int w, int h) =>
        resizeDimensions((width: w, height: h), settings.conversion);

    expect(result(320, 240), (width: 640, height: 480));
    expect(result(1280, 960), (width: 640, height: 480));
    expect(result(640, 480), (width: 640, height: 480));
    expect(result(240, 320), (width: 480, height: 640));
    expect(result(960, 1280), (width: 480, height: 640));
    expect(result(1920, 1080), (width: 854, height: 480));
    settings.presetHeight = 720;
    expect(result(1920, 1080), (width: 1280, height: 720));
  });

  test(
    'fractional and box sizes preserve the existing even rounding',
    () async {
      final settings = await AppSettings.load();
      PixelSize? result(int w, int h) =>
          resizeDimensions((width: w, height: h), settings.conversion);

      settings.resizeMultiplier = 0.5;
      expect(result(321, 241), (width: 160, height: 120));
      expect(result(3, 2), isNull);
      settings.videoCodec = VideoCodec.h265;
      expect(result(31, 32), (width: 14, height: 16));
      expect(
        resizeDimensions(
          (width: 31, height: 32),
          settings.conversion,
          kind: MediaKind.video,
        ),
        isNull,
      );
      settings.resizeMultiplier = 1;
      expect(result(321, 241), (width: 320, height: 240));
      settings.resizeMultiplier = 1.5;
      expect(result(321, 241), (width: 480, height: 360));
      settings
        ..sizeType = SizeType.custom
        ..customWidth = 501
        ..customHeight = 401;
      expect(result(1920, 1080), (width: 500, height: 282));
      expect(result(240, 320), (width: 300, height: 400));
      expect(result(1, 4096), isNull);
      settings.customWidth = 0;
      expect(result(321, 241), isNull);
    },
  );

  for (final legacy in ['upscale', 'downscale', 'ai']) {
    test('migrates $legacy while preserving effective settings', () async {
      SharedPreferences.setMockInitialValues({
        'scaleMode': legacy,
        'sizeType': 'multiplier',
        'multiplier': 3,
        'presetHeight': 1440,
        'customWidth': 899,
        'customHeight': 701,
        'videoCodec': 'h265',
        'videoQuality': 'high',
        'normalQuality': 'fast',
        'sameFolder': false,
        'outputDirectory': 'output',
        'renameOutput': false,
        'themeMode': 'system',
        'aiUseGpu': false,
        'aiModel': 'anime',
      });
      final settings = await AppSettings.load();
      expect(
        settings.scaleMode,
        legacy == 'ai' ? ScaleMode.ai : ScaleMode.resize,
      );
      expect(
        settings.sizeType,
        legacy == 'downscale' ? SizeType.preset : SizeType.multiplier,
      );
      expect(settings.resizeMultiplier, 3);
      expect(settings.aiMultiplier, 3);
      expect(settings.presetHeight, 1440);
      expect((settings.customWidth, settings.customHeight), (899, 701));
      expect(settings.videoCodec, VideoCodec.h265);
      expect(settings.videoQuality, VideoQuality.high);
      expect(settings.normalQuality, NormalQuality.fast);
      expect(settings.sameFolder, isFalse);
      expect(settings.outputDirectory, 'output');
      expect(settings.renameOutput, isFalse);
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.aiUseGpu, isFalse);
      expect(settings.aiModel, 'anime');
      settings
        ..sizeType = SizeType.multiplier
        ..resizeMultiplier = 0.5
        ..aiMultiplier = 4
        ..presetHeight = 480;
      await settings.save();
      final restored = await AppSettings.load();
      expect(restored.conversion, settings.conversion);
      expect(restored.themeMode, ThemeMode.system);
    });
  }

  test('recover invalid multiplier values independently', () async {
    SharedPreferences.setMockInitialValues({
      'multiplier': 4,
      'resizeMultiplier': '0.75',
      'aiMultiplier': 1.5,
      'outputDirectory': 'existing',
    });
    final settings = await AppSettings.load();
    expect(settings.resizeMultiplier, 2);
    expect(settings.aiMultiplier, 2);
    expect(settings.outputDirectory, 'existing');
  });
}
