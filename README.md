# メディア・スケーラー

Windows / macOS 共通のFlutterソースで動く、画像・動画のアップスケール／ダウンスケールアプリです。バージョン1.2.5ではWindowsの更新検出を安定化し、タイトルバーへ実行中のバージョンを表示します。

配布先は [GitHub Releases](https://github.com/skybluema891-dev/media-scaler/releases/latest) です。GitHub接続と更新運用は [自動リリースと更新通知](docs/自動リリースと更新通知.md) を参照してください。更新先は設定済みです。以前の1.1.2からは最初の1回だけ手動インストールしてください。

## 主な機能

- 画像・動画の複数選択、ドラッグ＆ドロップ
- 2～4倍、720p～4K、カスタム解像度
- 縦横比維持、縦向き素材対応
- 順次処理、進捗、残り時間、キャンセル
- H.264 / H.265、GPUエンコード自動検出、CPUフォールバック
- GPUの実動作テスト、GPU別高速プリセット、CPU高速プリセット
- 設定保存、重複しない出力名、日本語エラー、ログ
- ライト／ダーク／OS連動テーマ
- 起動時・手動の更新確認、OS／CPU別ダウンロード案内、バージョンスキップ

AI高画質化（Real-ESRGAN）、オフラインモデル、画像比較プレビューを搭載しています。AI動画は通常変換より大幅に時間がかかります。

## Windowsで起動する

プロジェクト直下の `00_メディア・スケーラー.exe` をダブルクリックしてください。
このファイルは必要なDLLとFFmpegが入ったRelease版を自動で起動します。
`app` フォルダは移動・削除しないでください。インストールする場合は直下の `01_インストール.exe` を使用してください。

## 開発環境での起動

1. Flutter SDKを用意します。
2. Windows版にはFFmpegとFFprobeが同梱済みです。macOS版は `FFmpeg導入ガイド.txt` を参照してください。
3. プロジェクト直下で次を実行します。

```powershell
flutter pub get
flutter run -d windows
```

macOSでは `flutter run -d macos` を使用します。

## ビルド

```powershell
flutter build windows
```

```bash
flutter build macos
```

WindowsビルドではGPL版FFmpegが実行ファイルの隣へ自動コピーされます。再配布時は同梱した `FFMPEG-LICENSE.txt` を保持し、`FFmpeg導入ガイド.txt` の注意事項を確認してください。

詳しい操作方法は `パラメーター設定ガイド.txt`、今回の実装範囲と制限は `PHASE_3_4_REPORT.txt`、配布用ビルドは `ビルドと配布ガイド.txt` を参照してください。
