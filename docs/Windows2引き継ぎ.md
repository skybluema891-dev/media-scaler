# Media Scaler の Windows 2 引き継ぎ

正式名称は **Media Scaler**。主開発PCは **Windows 2**。Windows 1の開発ソース、完成版、旧版、設定と復旧資料は復旧元として保存する。

## Gitと3フォルダ

リポジトリは `https://github.com/skybluema891-dev/media-scaler.git` の `main`。受け渡し時に指定されたSHAを `git rev-parse HEAD` で照合する。

```text
Media Scaler/
  app-layout.json
  開発環境-(ソースコード・テスト・検証ログ )/
    .git/
    lib/  test/  ai_worker/  windows/  macos/  scripts/  docs/
    tools/  build/  logs/  .verification/
  完成アプリ-(正式ビルド・配布ファイル)/
  ユーザーデータ-(設定・履歴・データベース)/
```

開発環境の閉じ括弧直前には半角空白が1文字ある。Git管理範囲は開発環境以下。管理ルートの対応表と兄弟2領域は端末内にあり、`config/app-layout.windows.json` を基準に初期化する。CIのcheckoutはGitルートを直接使い、ローカルの親や兄弟フォルダを必要としない。

## Windows 2の初回セットアップ

共有ドライブからは受け渡し資料を取得する。クローン先、ビルド先、稼働データはWindows 2のローカルディスクに準備する。Windows 2では指定の作業フォルダの `Media Scaler` を使う。以下の `$appRoot` は各端末の実フォルダに合わせる。既存クローンがある場合は、そのリモート・ブランチ・未コミット変更を確認してから取り込む。短縮名の既存領域があるときは先に対応を確認し、移行先を重複作成しない。

```powershell
$appRoot = '<この端末の Media Scaler 管理フォルダの絶対パス>'
$devRoot = Join-Path $appRoot '開発環境-(ソースコード・テスト・検証ログ )'
New-Item -ItemType Directory -Path $appRoot -Force | Out-Null
git clone --branch main https://github.com/skybluema891-dev/media-scaler.git $devRoot
if ($LASTEXITCODE) { throw 'clone failed' }
Set-Location -LiteralPath $devRoot
git rev-parse HEAD
python -B scripts/manage_windows.py setup
python -B scripts/manage_windows.py context
```

`setup` は兄弟領域と端末の対応表を作成する。既存フォルダを再利用し、対応表を更新するときは `logs/` に原本を保存する。Media Scaler専用の入口が、共通managerのスキーマ3の役割名をこの起動に限って渡す。導入済みの共通ツールは `CODEX_HOME` またはユーザーフォルダ下の `.codex` から取得する。未導入の場合は既存の共通ルールの端末別展開手順を使用する。

| 項目 | 準備するもの |
|---|---|
| Windows | Windows x64、PowerShell 7、Git for Windows |
| Flutter | CIで指定している Flutter 3.47.3 stable、Dart 3.13.3 |
| C++ | Visual Studioの「C++によるデスクトップ開発」、MSVC x64、CMake、Windows SDK。Windows 1の確認環境はVisual Studio 18.10 |
| Python | Python 3.13 x64。Windows 1は3.13.15。組み込み版も3.13.15 x64 |
| インストーラー | 深いインストール先に対応するInno Setup 7。Windows 2とCIは `./scripts/prepare_inno_windows.ps1` で公式7.1.1を準備する。準備済みの場合は再利用する。 |
| GPU | GPUメーカーのVulkan対応ドライバー。Real-ESRGANのGPU処理とFFmpegのハードウェアエンコードを端末ごとに確認する |

`flutter doctor -v`、`git --version`、`python --version`、`pwsh --version` を実行し、同じターミナルから各ツールを呼び出せることを確認する。GitHubへのpush認証はWindows 2のGit Credential Manager等で設定する。更新確認は公開Releaseを使用する。Windowsのローカルビルドに秘密値は不要。CIは `UPDATE_REPOSITORY` とGitHubが提供する `GH_TOKEN` を使う。macOSの署名・公証設定は [既存の手順](macOS正式署名と公証.md) にある。

Windows 2では、Flutter 3.47.3を `tools/sdk/flutter/`、Python 3.13.15 x64を `tools/sdk/python/`、Inno Setup 7.1.1を `tools/inno-7.1.1/` から使う。旧候補の再現用に6.7.4も `tools/inno/` に保持している。ローカルのテスト・ビルドは、日本語・空白・括弧を含むパスに対応するためFlutter SDKとビルド作業領域を一時的に別々の短いドライブ名で参照する。Flutter がプラグイン用シンボリックリンクを権限上作成できない場合は、ビルドの一時領域にディレクトリジャンクションを作成して続行する。SDKと依存キャッシュは次回も使う。Windows 2で下の例を実行するときは、必要に応じて `python` を `./tools/sdk/python/python.exe` に読み替える。

## 依存復元と確認用ビルド

初回はクローンしたGitルートから以下を実行する。PowerShellの実行ポリシーに従って、仮想環境の `Scripts` をそのターミナルのPATH先頭に置く。

```powershell
python -m venv .venv-media-scaler
$env:Path = "$(Join-Path $devRoot '.venv-media-scaler\Scripts');$env:Path"
python -m pip install -r ai_worker/requirements.txt
python -B scripts/prepare_tools.py
python -B scripts/build_worker.py
python -B scripts/manage_windows.py test --defer
$version = (Select-String -LiteralPath pubspec.yaml -Pattern '^version:\s*(\d+\.\d+\.\d+)\+').Matches[0].Groups[1].Value
python -B scripts/manage_windows.py build --version $version --defer
```

テストとビルドは共通清掃に登録され、立ち上げ時に `flutter pub get`、Dart静的解析、Flutterテスト、Release検証を行う。Windowsのネイティブツール向けに作業コピーと一時ディレクトリを `build/release-stage-<実行ID>/` に分離し、短いドライブ名で参照する。ビルドの清掃ラッパーでは宣言したログと要約だけを回収対象とする。候補のEXEと同梱物は `build/candidate/app/<版>/`、候補インストーラーは `build/candidate/dist/`、ビルドログは `build/windows-release.log`。検証要約は `logs/`、登録された一時実行領域は `.verification/`。

最初は候補の同梱フォルダから `Media Scaler.exe` を起動する。Windows 2で受け入れ確認が済んだ候補は、Gitルートから次のコマンドで完成アプリ領域に配置できる。既存の同版フォルダは保護される。候補版と完成版は、それぞれ同梱された `runtime.json` の相対パスでユーザーデータを参照する。

```powershell
python -B scripts/manage_windows.py run --purpose 'Place accepted Windows build' --defer -- pwsh -NoProfile -File scripts/promote_local_windows.ps1 -Version $version
python -B scripts/manage_windows.py finish --outcome success --task-id MediaScalerWindows2Acceptance
```

各作業依頼の終了前に `finish` を実行する。受け入れ途中では `--outcome incomplete` を指定する。初回は `cleanup.py sweep --project <開発環境の実パス>` で候補を確認する。正常終了した実行の明示出力は `finish` が回収し、要約と容量を `logs/task-finish-*.json` に記録する。調査中の出力は共通清掃の保持記録に従う。

## Git外のファイルとデータ

| 内容 | 取得元・配置 | 受け渡し |
|---|---|---|
| Real-ESRGAN Vulkanエンジンとモデル | [v0.2.5.0 Windowsアーカイブ](https://github.com/xinntao/Real-ESRGAN/releases/tag/v0.2.5.0) の20220424版。`prepare_tools.py` で `tools/ai/windows/` と `models/` に展開 | 開発に必要。再取得可能 |
| FFmpeg、FFprobe、ライセンス | [BtbN FFmpeg Builds](https://github.com/BtbN/FFmpeg-Builds) のGPL Win64 n8.1系。`prepare_tools.py` で `tools/ffmpeg/windows/` に取得。latestの中身は更新されるため、取得時の `PROVENANCE.json` を確認 | 開発に必要。再取得可能 |
| AI実行環境 | [Python 3.13.15 Windows埋め込み版](https://www.python.org/ftp/python/3.13.15/python-3.13.15-embed-amd64.zip) とPyPIのncnn 1.0.20260526、NumPy 2.5.3、Pillow 12.3.0。`build_worker.py` で `tools/ai/windows/python/` に構成 | 開発に必要。再取得可能 |
| 端末固有設定・履歴・変換出力 | 管理対象版はユーザーデータ領域の `shared_preferences.json` と `logs/`。インストーラーで通常導入した版は `%APPDATA%\com.example\media_scaler`。変換出力はアプリで指定したフォルダ。現行版に独立した履歴DBはない | 設定を引き継ぐ場合は、アプリ終了後に移行先をバックアップし、必要な設定JSONを選択コピーする。保存先の絶対パスはWindows 2で再選択する |
| アイコン原本、旧版、Windows 1の復旧記録 | アイコン原本はユーザーデータ領域。アプリに必要なアイコンはGitにある。旧版は完成アプリ領域。復旧資料は開発環境の `logs/` と `旧開発環境/` | Windows 1で保管。必要になったファイルだけ既存共有経由でSHA-256を照合しコピー |

アーカイブ・展開モデルのサイズとハッシュは、受け渡し用の `dependencies.json` を参照する。これはWindows 1で再取得した時点の値。Windows 1の環境変数やドライブ割り当て、認証・清掃台帳はWindows 2上で個別に確認する。共通ツールの配置先は端末の `CODEX_HOME` に従う。

## 受け入れ順と復旧

1. Windows 2で取得SHA、3フォルダ名、`context` の出力を照合する。
2. 依存復元とWindowsビルドを実施し、`Media Scaler` のウィンドウ名、ファイルの追加・削除、保存先とファイル名設定、再起動後の設定保持を確認する。
3. 短い合成画像・動画で通常変換、CPU画像AI、Vulkan動画AIを試し、出力を確認する。更新確認と清掃のドライランも確認する。
4. 必要なら検証済みインストーラーで上書き導入し、ショートカットと設定継承を確認する。その結果を記録してWindows 2への切り替えを確定する。

主要機能は画像・動画の拡縮、AI高画質化、GPU処理とCPUフォールバック、設定・出力名選択、更新通知。Windows 1の現行パスではFlutterテスト19件とRelease確認12件に合格した。候補の起動時にウィンドウ名を確認し、短い動画のH.264／H.265、CPU画像AI、Vulkan動画AI、既存設定の読み込み、公開Releaseの取得を検証した。Windows 2のGUI操作、GPUドライバー、インストールと再起動後の保存は受け入れ待ち。長時間変換は今回の引き継ぎ判定に含めていない。

Windows 1は既存のインストール先と完成アプリにある版から起動できる。必要に応じてアプリを終了し、設定を退避してから開発環境の `logs/backup-appdata/` と照合する。前回の復旧資料は `logs/Media Scaler Windows 1 移行記録.txt`。フォルダ名変更前の清掃台帳には旧パスが記録されているため、現行パスの登録とは別に保全する。

## Windows 2実機の記録

- 2026年11月21日、`WINDOWS2` の Windows 11 Pro x64で、`main` を引き継ぎ基準 `10c5cd6a17f579e6135d6c91fefa192939af10f0` と照合した。今後は両端末で別々のローカル作業フォルダを使い、Windows 1から再開するときは先にGitHubの最新 `main` を取得する。
- Flutter 3.47.3／Dart 3.13.3、Python 3.13.15、Inno Setup 6.7.4、既存の Visual Studio Build Tools 2022 17.14.41／Windows SDK 10.0.26100.0 を使用した。初回のプラグイン用リンク作成エラーは開発者モードを有効化後に解消した。
- Dart静的解析、Flutterテスト19件、リリース手順テスト12件、AIワーカーテスト5件を通過した。Real-ESRGANモデル10ファイルと埋め込みPythonアーカイブは引き継ぎ時のハッシュに一致した。FFmpegは取得時点の n8.1.3 系を使用した。
- エンジン単体でH.264の短い動画変換、CPU画像AI、Intel Iris Xe GraphicsでVulkanの画像／動画AIを確認した。AI動画は2フレームの合成入力を2倍に変換し、FFprobeでH.264・96×64を読み取った。
- Windows x64のReleaseビルドとインストーラーの生成に成功した。同梱エンジンを使ったAIワーカーテストも5件通過した。候補版の画面で、合成PNGとH.264 MP4の読み込み、2倍変換、保存、更新確認を実施した。画面に完了2件が表示され、両ファイルの128×96の出力を外部ツールで読み取った。
- 受け入れ済みのローカル配布物は `完成アプリ-(正式ビルド・配布ファイル)/Windows-1.2.5/` の `Media Scaler.exe` と `Media Scaler Setup.exe`。開発環境の元パスを一時的に参照できなくした状態で同フォルダの `Media Scaler.exe` が起動し、ユーザーデータ領域に保存した倍率設定を再読み込みした。稼働ログの保存先も同領域で確認した。
- Windows 2で開発とローカルビルドを継続できる。公開版v1.2.4・v1.2.5からの上書き、ショートカット・旧設定の継承、および実用化に向けた残件は [Windows 2受け入れ記録](Windows2受け入れ.md) を参照する。Windows 1の設定の取り込みは必要になった時点で行う。
