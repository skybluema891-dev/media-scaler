import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'screens/home_screen.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        title: 'メディア・スケーラー${version.isEmpty ? '' : ' v$version'}',
        themeMode: settings.themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3659c9)),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff8ea7ff),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: HomeScreen(
          settings: settings,
          checkToolsOnStart: checkToolsOnStart,
        ),
      ),
    );
  }
}
