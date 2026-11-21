import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

void configureWindowsStorage() {
  if (!Platform.isWindows) return;
  final provider = _MediaScalerWindowsPaths();
  PathProviderPlatform.instance = provider;
  final preferences = SharedPreferencesWindows();
  // The Windows preferences implementation has its own path provider.
  // ignore: invalid_use_of_visible_for_testing_member
  preferences.pathProvider = provider;
  SharedPreferencesStorePlatform.instance = preferences;
}

class _MediaScalerWindowsPaths extends PathProviderWindows {
  @override
  Future<String?> getApplicationSupportPath() =>
      _legacyDirectory('APPDATA');

  @override
  Future<String?> getApplicationCachePath() =>
      _legacyDirectory('LOCALAPPDATA');

  Future<String?> _legacyDirectory(String environmentKey) async {
    final base = Platform.environment[environmentKey];
    if (base == null || !p.isAbsolute(base)) return null;
    // These components identify existing data independently of VERSIONINFO.
    final directory = Directory(p.join(base, 'com.example', 'media_scaler'));
    await directory.create(recursive: true);
    return directory.path;
  }
}
