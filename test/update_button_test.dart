import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_scaler/screens/update_button.dart';
import 'package:media_scaler/services/update_service.dart';

final manifest = jsonDecode(
  File('test/fixtures/latest-1.2.6.json').readAsStringSync(),
) as Map<String, dynamic>;
AppUpdate candidate(String target) => UpdateService.parseRelease(
  manifest,
  currentVersion: '1.2.5',
  repository: 'skybluema891-dev/media-scaler',
  target: target,
)!;

Widget screen({
  Future<AppUpdate?> Function()? check,
  Future<bool> Function(Uri)? open,
}) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      actions: [
        UpdateButton(
          checkForUpdate: check ?? () async => candidate('windows-x64'),
          openUrl: open,
        ),
      ],
    ),
    body: const Text('変換画面'),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'MediaScaler',
      packageName: 'example.scaler',
      version: '1.2.5',
      buildNumber: '10',
      buildSignature: '',
    );
  });
  for (final entry in {
    'windows-x64': 'windows-setup.exe',
    'macos-arm64': 'macos-arm64.dmg',
    'macos-x86_64': 'macos-x86_64.dmg',
  }.entries) {
    testWidgets('published 1.2.5 detects candidate for ${entry.key}', (
      tester,
    ) async {
      Uri? opened;
      await tester.pumpWidget(
        screen(
          check: () async => candidate(entry.key),
          open: (url) async {
            opened = url;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1.2.5 → 1.2.6'), findsOneWidget);
      final name = 'MediaScaler-1.2.6-${entry.value}';
      expect(find.text(name), findsOneWidget);
      await tester.tap(find.text('ダウンロード'));
      await tester.pumpAndSettle();
      expect(
        opened.toString(),
        'https://github.com/skybluema891-dev/media-scaler/releases/download/v1.2.6/$name',
      );
      expect(find.text('変換画面'), findsOneWidget);
    });
  }
  testWidgets('candidate changes opens versioned release notes', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      screen(
        open: (url) async {
          opened = url;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('変更内容'));
    await tester.pumpAndSettle();
    expect(
      opened.toString(),
      'https://github.com/skybluema891-dev/media-scaler/releases/tag/v1.2.6',
    );
  });
  testWidgets('skip persists but manual check still shows update', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('この版をスキップ'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update.skippedVersion'), '1.2.6');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Media Scaler の新しいバージョンがあります'), findsNothing);
    await tester.tap(find.byTooltip('更新を確認'));
    await tester.pumpAndSettle();
    expect(find.text('Media Scaler の新しいバージョンがあります'), findsOneWidget);
  });
  testWidgets('offline startup stays quiet; manual check explains failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(check: () async => throw const UpdateException('接続できません')),
    );
    await tester.pumpAndSettle();
    expect(find.text('接続できません'), findsNothing);
    await tester.tap(find.byTooltip('更新を確認'));
    await tester.pumpAndSettle();
    expect(find.text('接続できません'), findsOneWidget);
  });
  testWidgets('latest version feedback on manual check', (tester) async {
    await tester.pumpWidget(screen(check: () async => null));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更新を確認'));
    await tester.pumpAndSettle();
    expect(find.text('バージョン 1.2.5 は最新です。'), findsOneWidget);
  });
}
