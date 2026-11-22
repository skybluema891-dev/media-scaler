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

## PRブランチからの候補検証

Actionsの「Build desktop releases」で検証するブランチを選び、`verify_candidate` を有効にして実行する。CLIからは次の指定を使う。

```sh
gh workflow run release.yml --ref windows2-full-acceptance -f verify_candidate=true
```

この入力ではApple SiliconとIntelのホストでローカル版番号を使い、Release作成・タグ付けを含む公開ジョブはスキップされる。通常のmainへのバージョン更新・タグ・公開用手動実行は従来の条件で動く。

署名用設定5項目が揃った候補ではDeveloper ID署名とApple公証を実行する。候補検証で設定が不足しているときは警告を記録し、`candidate-…-adhoc` の成果物にビルドとパッケージの結果を残す。正式配布の判定には `candidate-…-notarized` の結果が必要となる。公開用ジョブは必要な設定が不足すると停止する。

各ホストでDMGを読み取り専用でマウントし、Applications相当へコピーしたアプリとZIP展開物のバージョン・署名・アーキテクチャ・実行権限を調べる。コピーしたアプリのGUIウィンドウを検出し、同梱エンジンで画像と音声付き動画をテストする。SHA-256と、取得可能な場合はGUIのウィンドウ画像を成果物に含める。ホスト上の自動確認と、利用者のMacでの日本語表示・操作確認は受け入れ記録で区別する。

## 2026年11月22日　候補 1.2.6+11 の検証記録

PR #1 のソース `863c06c038e6bcced6187f76f5d013976d48f074` を指定して、GitHubホストのmacOS 15上で候補を作成した。Apple SiliconとIntelの両ジョブが成功し、Windowsビルドと公開ジョブはスキップされた。[候補検証の実行記録](https://github.com/skybluema891-dev/media-scaler/actions/runs/44978029748)

| CPU | 候補の署名 | 成果物 |
| --- | --- | --- |
| Apple Silicon arm64 | Ad-hoc | [ZIP・DMG・SHA-256・ウィンドウ画像](https://github.com/skybluema891-dev/media-scaler/actions/runs/44978029748/artifacts/14735944504) |
| Intel x86_64 | Ad-hoc | [ZIP・DMG・SHA-256・ウィンドウ画像](https://github.com/skybluema891-dev/media-scaler/actions/runs/44978029748/artifacts/14737021681) |

両ホストで、DMGからApplications相当へコピーしたアプリとZIP内のアプリについて、版・アーキテクチャ・実行権限・Ad-hoc署名を検証した。両ホストともFlutterテスト26件が成功した。同梱AIワーカーのテストは各5件が成功し、Windows専用の1件はスキップされた。画像の拡大と音声付き動画の出力は、コピーしたアプリの同梱ワーカーを使って確認した。

Windows 2に保存した両候補のZIPとDMGについて、取得時にActionsのアーカイブダイジェストとホストが記録した各ファイルのSHA-256を照合した。保存先は `build/candidate-macos-863c06c038e6/{arm64,x86_64}/`。各ディレクトリの `window-macos-<CPU>.png` を目視し、両方で「Media Scaler」の暗色画面に「ファイル一覧」「画像・動画を追加」「処理設定」「互換性優先 (H.264)」が読めることを確認した。表示されたMacのネイティブタイトルバーは明色だった。

この実行ではリポジトリのActions Secretsの登録数は0件で、Macジョブでも署名設定が不足していた。Developer ID署名、Hardened Runtime・タイムスタンプ、Apple公証、チケット付与、Gatekeeperによる受け入れは正式配布前に両CPUで確認する。Mac利用端末でのGUIによる素材追加・変換・保存・再起動も残っている。

公開版は v1.2.5。更新通知では1.2.6の候補マニフェストをfixtureに使い、リリースノート、OS・CPU別のダウンロード、スキップと通信失敗を検査した。実際の v1.2.6 へのオンライン更新確認は正式公開後に行う。
