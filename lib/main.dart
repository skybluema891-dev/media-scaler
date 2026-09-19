import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(MediaScalerApp(settings: settings));
}

class MediaScalerApp extends StatelessWidget {
  const MediaScalerApp({
    super.key,
    required this.settings,
    this.checkToolsOnStart = true,
  });
  final AppSettings settings;
  final bool checkToolsOnStart;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'メディア・スケーラー',
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
