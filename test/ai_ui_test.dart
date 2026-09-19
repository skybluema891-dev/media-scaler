import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_scaler/main.dart';
import 'package:media_scaler/models/media_item.dart';
import 'package:media_scaler/screens/home_screen.dart';
import 'package:media_scaler/services/app_settings.dart';

void main() {
  testWidgets('AI settings render and persist without overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    settings.scaleMode = ScaleMode.ai;
    settings.aiModel = 'anime';
    settings.aiQuality = NormalQuality.fast;
    settings.aiVideoFps = 24;
    await settings.save();
    final restored = await AppSettings.load();
    expect(restored.aiModel, 'anime');
    expect(restored.aiQuality, NormalQuality.fast);
    expect(restored.aiVideoFps, 24);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaScalerApp(settings: settings, checkToolsOnStart: false),
    );
    await tester.pump();
    expect(find.text('AIの品質'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('imported file can be removed from the list', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final file = File('pubspec.yaml');

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          settings: settings,
          checkToolsOnStart: false,
          initialItems: [MediaItem(file.path, MediaKind.video)],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('pubspec.yaml'), findsOneWidget);
    expect(find.textContaining('1 ファイル'), findsOneWidget);

    await tester.tap(find.byTooltip('一覧から削除'));
    await tester.pump();
    expect(find.text('pubspec.yaml'), findsNothing);
    expect(find.textContaining('0 ファイル'), findsOneWidget);
  });
}
