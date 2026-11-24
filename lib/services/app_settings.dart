import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScaleMode { resize, ai }

enum SizeType { multiplier, preset, custom }

enum NormalQuality { fast, standard, high }

enum VideoQuality { compact, standard, high, maximum }

enum VideoCodec { h264, h265 }

const resizeMultipliers = <double>[0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4];
const aiMultipliers = [2, 3, 4];
const sizePresets = [480, 720, 1080, 1440, 2160];

String formatMultiplier(double value) =>
    value.toString().replaceFirst(RegExp(r'\.0$'), '');

typedef ConversionSettings = ({
  ScaleMode scaleMode,
  SizeType sizeType,
  double resizeMultiplier,
  int aiMultiplier,
  int presetHeight,
  int customWidth,
  int customHeight,
  NormalQuality normalQuality,
  VideoQuality videoQuality,
  VideoCodec videoCodec,
  int jpegQuality,
  bool useGpu,
  bool sameFolder,
  bool renameOutput,
  String outputDirectory,
  NormalQuality aiQuality,
  String aiModel,
  bool aiUseGpu,
  int aiVideoFps,
});

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);
  final SharedPreferences _prefs;

  ScaleMode scaleMode = ScaleMode.resize;
  SizeType sizeType = SizeType.multiplier;
  double resizeMultiplier = 2;
  int aiMultiplier = 2;
  int presetHeight = 1080;
  int customWidth = 1920;
  int customHeight = 1080;
  NormalQuality normalQuality = NormalQuality.standard;
  VideoQuality videoQuality = VideoQuality.standard;
  VideoCodec videoCodec = VideoCodec.h264;
  int jpegQuality = 90;
  bool useGpu = true;
  bool sameFolder = true;
  bool renameOutput = true;
  String outputDirectory = '';
  ThemeMode themeMode = ThemeMode.dark;
  NormalQuality aiQuality = NormalQuality.standard;
  String aiModel = 'photo';
  bool aiUseGpu = true;
  int aiVideoFps = 30;

  ConversionSettings get conversion => (
    scaleMode: scaleMode,
    sizeType: sizeType,
    resizeMultiplier: resizeMultiplier,
    aiMultiplier: aiMultiplier,
    presetHeight: presetHeight,
    customWidth: customWidth,
    customHeight: customHeight,
    normalQuality: normalQuality,
    videoQuality: videoQuality,
    videoCodec: videoCodec,
    jpegQuality: jpegQuality,
    useGpu: useGpu,
    sameFolder: sameFolder,
    renameOutput: renameOutput,
    outputDirectory: outputDirectory,
    aiQuality: aiQuality,
    aiModel: aiModel,
    aiUseGpu: aiUseGpu,
    aiVideoFps: aiVideoFps,
  );

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
    final savedMode = prefs.getString('scaleMode');
    value.scaleMode = savedMode == 'ai' ? ScaleMode.ai : ScaleMode.resize;
    value.sizeType = _enumValue(
      SizeType.values,
      prefs.getString('sizeType'),
      SizeType.multiplier,
    );
    final oldMultiplier = prefs.get('multiplier');
    final normal = prefs.get('resizeMultiplier') ?? oldMultiplier;
    if (normal is num && resizeMultipliers.contains(normal)) {
      value.resizeMultiplier = normal.toDouble();
    }
    final ai = prefs.get('aiMultiplier') ?? oldMultiplier;
    if (ai is num && aiMultipliers.contains(ai)) {
      value.aiMultiplier = ai.toInt();
    }
    final preset = prefs.getInt('presetHeight');
    if (preset != null && sizePresets.contains(preset)) {
      value.presetHeight = preset;
    }
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
    value.renameOutput = prefs.getBool('renameOutput') ?? true;
    value.outputDirectory = prefs.getString('outputDirectory') ?? '';
    value.themeMode = _enumValue(
      ThemeMode.values,
      prefs.getString('themeMode'),
      ThemeMode.dark,
    );
    if (savedMode == 'downscale' && value.sizeType == SizeType.multiplier) {
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
      _prefs.setDouble('resizeMultiplier', resizeMultiplier),
      _prefs.setInt('aiMultiplier', aiMultiplier),
      _prefs.setInt('presetHeight', presetHeight),
      _prefs.setInt('customWidth', customWidth),
      _prefs.setInt('customHeight', customHeight),
      _prefs.setString('normalQuality', normalQuality.name),
      _prefs.setString('videoQuality', videoQuality.name),
      _prefs.setString('videoCodec', videoCodec.name),
      _prefs.setInt('jpegQuality', jpegQuality),
      _prefs.setBool('useGpu', useGpu),
      _prefs.setBool('sameFolder', sameFolder),
      _prefs.setBool('renameOutput', renameOutput),
      _prefs.setString('outputDirectory', outputDirectory),
      _prefs.setString('themeMode', themeMode.name),
    ]);
    notifyListeners();
  }
}
