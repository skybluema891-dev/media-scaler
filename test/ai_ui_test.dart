import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_scaler/main.dart';
import 'package:media_scaler/models/media_item.dart';
import 'package:media_scaler/screens/home_screen.dart';
import 'package:media_scaler/screens/preview_dialog.dart';
import 'package:media_scaler/services/app_settings.dart';

void main() {
  test('new profiles use dark, saved theme choices survive loading', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await AppSettings.load()).themeMode, ThemeMode.dark);
    for (final choice in ThemeMode.values) {
      SharedPreferences.setMockInitialValues({'themeMode': choice.name});
      final settings = await AppSettings.load();
      expect(settings.themeMode, choice);
      await settings.save();
      expect((await AppSettings.load()).themeMode, choice);
    }
  });

  testWidgets(
    'compact window keeps settings and action bar reachable at larger text',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(420, 300);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MediaScalerApp(
          settings: await AppSettings.load(),
          checkToolsOnStart: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
      await tester.ensureVisible(find.text('保存先フォルダを選ぶ'));
      await tester.pumpAndSettle();
      expect(find.text('保存先フォルダを選ぶ').hitTestable(), findsOneWidget);
      expect(find.text('すべて変換開始').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'comparison slider exposes its changing keyboard value and Escape closes the route',
    (tester) async {
      tester.view.physicalSize = const Size(420, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const icon =
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    const PreviewDialog(original: icon, result: icon),
              ),
              child: const Text('プレビュー'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('プレビュー'));
      await tester.pumpAndSettle();
      final slider = find.byType(Slider);
      final boundary = find.semantics.byLabel('比較境界');
      expect(boundary, findsOne);
      expect(boundary.evaluate().single.value, '元画像 50パーセント');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final value = tester.widget<Slider>(slider).value;
      expect(value, greaterThan(.5));
      expect(
        boundary.evaluate().single.value,
        '元画像 ${(value * 100).round()}パーセント',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(slider, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
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
        version: '1.2.5',
        checkToolsOnStart: false,
      ),
    );
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'Media Scaler 1.2.5',
    );
    expect(find.text('Media Scaler'), findsOneWidget);
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
