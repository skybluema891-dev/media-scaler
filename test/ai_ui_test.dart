import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_scaler/main.dart';
import 'package:media_scaler/models/media_item.dart';
import 'package:media_scaler/screens/home_screen.dart';
import 'package:media_scaler/services/app_settings.dart';

void main() {
  testWidgets('output rename choice is selectable and persisted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaScalerApp(
        settings: settings,
        version: '1.2.3',
        checkToolsOnStart: false,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'メディア・スケーラー v1.2.3',
    );
    await tester.ensureVisible(find.text('変更OK（サイズを付ける）').first);
    await tester.tap(find.text('変更OK（サイズを付ける）').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('変更NG（サイズを付けない）').last);
    await tester.pumpAndSettle();
    expect(settings.renameOutput, isFalse);
    expect((await AppSettings.load()).renameOutput, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mac startup size places drop area left of settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaScalerApp(settings: settings, checkToolsOnStart: false),
    );
    await tester.pump();
    final drop = find.text('画像・動画をここへドラッグ＆ドロップ');
    final panel = find.text('処理設定');
    expect(drop, findsOneWidget);
    expect(tester.getRect(drop).right, lessThan(tester.getRect(panel).left));
    expect(tester.takeException(), isNull);
  });

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
