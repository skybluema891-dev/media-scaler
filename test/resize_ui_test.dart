import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_scaler/models/media_item.dart';
import 'package:media_scaler/screens/home_screen.dart';
import 'package:media_scaler/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('size controls preserve mode-specific values and update rows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final items = [
      for (final (w, h, icon) in [
        (320, 240, 16),
        (1280, 960, 32),
        (640, 480, 64),
      ])
        MediaItem(
          'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$icon.png',
          MediaKind.image,
        )..info = MediaInfo(width: w, height: h),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          settings: settings,
          checkToolsOnStart: false,
          initialItems: items,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    expect(find.text('サイズ変換'), findsOneWidget);
    expect(find.text('AI高画質化'), findsOneWidget);
    expect(find.text('拡大'), findsNothing);
    expect(find.text('縮小'), findsNothing);
    await tap(find.text('2倍'));
    await tap(find.text('0.5倍').hitTestable().last);
    expect(find.text('320×240 → 160×120　縮小'), findsOneWidget);
    await tap(find.text('AI高画質化'));
    expect(find.text('320×240 → 160×120　縮小'), findsNothing);
    await tap(find.text('2倍'));
    expect(find.text('0.5倍'), findsNothing);
    await tap(find.text('3倍').hitTestable().last);
    await tap(find.text('サイズ変換'));
    expect(find.text('0.5倍'), findsOneWidget);
    final restored = await AppSettings.load();
    expect(restored.resizeMultiplier, 0.5);
    expect(restored.aiMultiplier, 3);

    await tap(find.text('倍率で指定'));
    await tap(find.text('プリセットから選ぶ').hitTestable().last);
    await tap(find.text('1080p'));
    for (final preset in sizePresets) {
      expect(find.text('${preset}p'), findsWidgets);
    }
    await tap(find.text('480p').hitTestable().last);
    expect(find.text('320×240 → 640×480　拡大'), findsOneWidget);
    expect(find.text('1280×960 → 640×480　縮小'), findsOneWidget);
    expect(find.text('640×480 → 640×480　同じサイズ'), findsOneWidget);
    expect((await AppSettings.load()).presetHeight, 480);
    expect(tester.takeException(), isNull);
  });
}
