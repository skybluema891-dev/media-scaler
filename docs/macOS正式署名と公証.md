# macOS正式署名とApple公証

GitHub Releaseへ公開するmacOS版は、Developer ID Application証明書による署名とApple公証を必須とします。署名情報や公証情報が不足している場合、GitHub ActionsはMac成果物を作成せず、Releaseも公開しません。

## 初回設定

1. Apple Developer Programへ加入し、契約を有効にします。
2. Apple DeveloperのCertificatesで `Developer ID Application` 証明書を作成し、秘密鍵を含む`.p12`としてキーチェーンから書き出します。
3. App Store Connectの「ユーザとアクセス」→「統合」からAPIキーを作成し、`.p8`、Key ID、Issuer IDを控えます。
4. GitHubリポジトリの Settings → Secrets and variables → Actions に次を登録します。

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | `.p12`をBase64化した文字列 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12`書き出し時のパスワード |
| `APPLE_API_KEY_P8_BASE64` | App Store Connect APIキー`.p8`をBase64化した文字列 |
| `APPLE_API_KEY_ID` | APIキーのKey ID |
| `APPLE_API_ISSUER_ID` | APIキーのIssuer ID |

macOSでBase64文字列をクリップボードへ入れる例：

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

証明書やAPIキーの実ファイルはリポジトリへ追加しません。

## Release時の自動検査

`pubspec.yaml`のバージョンを上げて`main`へpushすると、Windows、Mac ARM64、Mac Intelを同じバージョンでビルドします。Macジョブは次をすべて確認します。

- アプリ本体、Flutter Framework、FFmpeg、Pythonワーカー、ネイティブライブラリのDeveloper ID署名
- Hardened Runtimeとタイムスタンプ
- `.app`のApple公証と公証チケットの付与
- Applications相当の別フォルダへコピーした後の署名・実行権限・同梱ツール
- DMGのDeveloper ID署名、Apple公証、公証チケット
- Gatekeeperによる`.app`とDMGの受け入れ

全項目が成功した場合だけGitHub Releaseを公開します。アプリの更新確認はReleaseの`latest` APIと`latest.json`を使用するため、Windows版とMac版は同じ公開バージョンを検出します。

## ローカルビルド

開発中のローカルビルドでは従来どおりAd-hoc署名を利用できます。配布用と同じ厳格な検査を行う場合は、署名・公証用の環境変数を設定し、`REQUIRE_MACOS_NOTARIZATION=1`で`build_macos.sh`を実行します。
