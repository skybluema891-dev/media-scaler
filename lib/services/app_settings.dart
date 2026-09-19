import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScaleMode { upscale, downscale, ai }

enum SizeType { multiplier, preset, custom }

enum NormalQuality { fast, standard, high }

enum VideoQuality { compact, standard, high, maximum }

enum VideoCodec { h264, h265 }

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);
  final SharedPreferences _prefs;

  ScaleMode scaleMode = ScaleMode.upscale;
  SizeType sizeType = SizeType.multiplier;
  int multiplier = 2;
  int presetHeight = 1080;
  int customWidth = 1920;
  int customHeight = 1080;
  NormalQuality normalQuality = NormalQuality.standard;
  VideoQuality videoQuality = VideoQuality.standard;
  VideoCodec videoCodec = VideoCodec.h264;
  int jpegQuality = 90;
  bool useGpu = true;
  bool sameFolder = true;
  String outputDirectory = '';
  ThemeMode themeMode = ThemeMode.system;
  NormalQuality aiQuality = NormalQuality.standard;
  String aiModel = 'photo';
  bool aiUseGpu = true;
  int aiVideoFps = 30;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = AppSettings._(prefs);
    value.aiQuality = _enumValue(
      NormalQuality.values,
      prefs.getString('aiQuality'),
      NormalQuality.standard,
    );
    value.aiModel = prefs.getString('aiModel') == 'anime' ? 'anime' : 'photo';
    value.aiUseGpu = prefs.getBool('aiUseGpu') ?? true;
    value.aiVideoFps = switch (prefs.getInt('aiVideoFps')) {
      0 => 0,
      24 => 24,
      _ => 30,
    };
    value.scaleMode = _enumValue(
      ScaleMode.values,
      prefs.getString('scaleMode'),
      ScaleMode.upscale,
    );
    value.sizeType = _enumValue(
      SizeType.values,
      prefs.getString('sizeType'),
      SizeType.multiplier,
    );
    value.multiplier = prefs.getInt('multiplier') ?? 2;
    value.presetHeight = prefs.getInt('presetHeight') ?? 1080;
    value.customWidth = prefs.getInt('customWidth') ?? 1920;
    value.customHeight = prefs.getInt('customHeight') ?? 1080;
    value.normalQuality = _enumValue(
      NormalQuality.values,
      prefs.getString('normalQuality'),
      NormalQuality.standard,
    );
    value.videoQuality = _enumValue(
      VideoQuality.values,
      prefs.getString('videoQuality'),
      VideoQuality.standard,
    );
    value.videoCodec = _enumValue(
      VideoCodec.values,
      prefs.getString('videoCodec'),
      VideoCodec.h264,
    );
    value.jpegQuality = prefs.getInt('jpegQuality') ?? 90;
    value.useGpu = prefs.getBool('useGpu') ?? true;
    value.sameFolder = prefs.getBool('sameFolder') ?? true;
    value.outputDirectory = prefs.getString('outputDirectory') ?? '';
    value.themeMode = _enumValue(
      ThemeMode.values,
      prefs.getString('themeMode'),
      ThemeMode.system,
    );
    if (value.scaleMode == ScaleMode.downscale &&
        value.sizeType == SizeType.multiplier) {
      value.sizeType = SizeType.preset;
    }
    return value;
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  Future<void> save() async {
    await Future.wait([
      _prefs.setString('aiQuality', aiQuality.name),
      _prefs.setString('aiModel', aiModel),
      _prefs.setBool('aiUseGpu', aiUseGpu),
      _prefs.setInt('aiVideoFps', aiVideoFps),
      _prefs.setString('scaleMode', scaleMode.name),
      _prefs.setString('sizeType', sizeType.name),
      _prefs.setInt('multiplier', multiplier),
      _prefs.setInt('presetHeight', presetHeight),
      _prefs.setInt('customWidth', customWidth),
      _prefs.setInt('customHeight', customHeight),
      _prefs.setString('normalQuality', normalQuality.name),
      _prefs.setString('videoQuality', videoQuality.name),
      _prefs.setString('videoCodec', videoCodec.name),
      _prefs.setInt('jpegQuality', jpegQuality),
      _prefs.setBool('useGpu', useGpu),
      _prefs.setBool('sameFolder', sameFolder),
      _prefs.setString('outputDirectory', outputDirectory),
      _prefs.setString('themeMode', themeMode.name),
    ]);
    notifyListeners();
  }
}
