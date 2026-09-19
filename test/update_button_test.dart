import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_scaler/screens/update_button.dart';
import 'package:media_scaler/services/update_service.dart';

final update = AppUpdate(
  currentVersion: '1.2.0',
  version: '1.3.0',
  releaseUrl: Uri.parse(
    'https://github.com/example/scaler/releases/tag/v1.3.0',
  ),
  downloadUrl: Uri.parse(
    'https://github.com/example/scaler/releases/download/v1.3.0/MediaScaler-1.3.0-macos-arm64.dmg',
  ),
  assetName: 'MediaScaler-1.3.0-macos-arm64.dmg',
);

Widget screen({
  Future<AppUpdate?> Function()? check,
  Future<bool> Function(Uri)? open,
}) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      actions: [
        UpdateButton(
          checkForUpdate: check ?? () async => update,
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
      version: '1.2.0',
      buildNumber: '4',
      buildSignature: '',
    );
  });
  testWidgets('startup notification and download use correct URL', (
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
    expect(find.text('新しいバージョンがあります'), findsOneWidget);
    expect(find.text('1.2.0 → 1.3.0'), findsOneWidget);
    await tester.tap(find.text('ダウンロード'));
    await tester.pumpAndSettle();
    expect(opened, update.downloadUrl);
    expect(find.text('変換画面'), findsOneWidget);
  });
  testWidgets('skip persists but manual check still shows update', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('この版をスキップ'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update.skippedVersion'), '1.3.0');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('新しいバージョンがあります'), findsNothing);
    await tester.tap(find.byTooltip('更新を確認'));
    await tester.pumpAndSettle();
    expect(find.text('新しいバージョンがあります'), findsOneWidget);
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
    expect(find.text('バージョン 1.2.0 は最新です。'), findsOneWidget);
  });
}
