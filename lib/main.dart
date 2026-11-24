import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_theme.dart';
import 'screens/home_screen.dart';
import 'services/app_settings.dart';
import 'services/windows_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureWindowsStorage();
  final settings = await AppSettings.load();
  final package = await PackageInfo.fromPlatform();
  runApp(MediaScalerApp(settings: settings, version: package.version));
}

class MediaScalerApp extends StatelessWidget {
  const MediaScalerApp({
    super.key,
    required this.settings,
    this.checkToolsOnStart = true,
    this.version = '',
  });
  final AppSettings settings;
  final bool checkToolsOnStart;
  final String version;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Media Scaler${version.isEmpty ? '' : ' $version'}',
        themeMode: settings.themeMode,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: HomeScreen(
          settings: settings,
          checkToolsOnStart: checkToolsOnStart,
        ),
      ),
    );
  }
}
