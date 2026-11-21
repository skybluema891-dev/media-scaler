# Media Scaler の Windows 2 引き継ぎ

正式名称は **Media Scaler**。今後の主開発PCは **Windows 2**。受け入れ状態は **準備済み・Windows 2実機での受け入れ待ち**。受け入れが終わるまで、Windows 1の開発ソース、完成版、旧版、設定と復旧資料を保存する。

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

共有ドライブからは受け渡し資料を取得する。クローン先、ビルド先、稼働データはWindows 2のローカルディスクに準備する。パスを短くするため、下の例ではユーザーフォルダ直下の `Dev` を使う。既存クローンがある場合は、そのリモート・ブランチ・未コミット変更を確認してから取り込む。短縮名の既存領域があるときは先に対応を確認し、移行先を重複作成しない。

```powershell
$appRoot = Join-Path $env:USERPROFILE 'Dev\Media Scaler'
$devRoot = Join-Path $appRoot '開発環境-(ソースコード・テスト・検証ログ )'
New-Item -ItemType Directory -Path $appRoot -Force | Out-Null
git clone --branch main https://github.com/skybluema891-dev/media-scaler.git $devRoot
if ($LASTEXITCODE) { throw 'clone failed' }
Set-Location -LiteralPath $devRoot
git rev-parse HEAD
python -B scripts/manage_windows.py setup
python -B scripts/manage_windows.py context
```

`setup` は空の兄弟領域と端末の対応表を作成する。既存の実フォルダを再利用し、既知の旧対応表を更新するときは `logs/app-layout.before-windows2.json` に原本を保存する。Media Scaler専用の入口が、共通managerのスキーマ3の役割名をこの起動に限って渡す。導入済みの共通ツールは `CODEX_HOME` またはユーザーフォルダ下の `.codex` から取得する。未導入の場合は既存の共通ルールの端末別展開手順を使用する。

| 項目 | 準備するもの |
|---|---|
| Windows | Windows x64、PowerShell 7、Git for Windows |
| Flutter | CIで指定している Flutter 3.47.3 stable、Dart 3.13.3 |
| C++ | Visual Studioの「C++によるデスクトップ開発」、MSVC x64、CMake、Windows SDK。Windows 1の確認環境はVisual Studio 18.10 |
| Python | Python 3.13 x64。Windows 1は3.13.15。組み込み版も3.13.15 x64 |
| インストーラー | Inno Setup 6または7。標準のインストール先で検出できないときは `scripts/build_windows.ps1 -Iscc <パス>` |
| GPU | GPUメーカーのVulkan対応ドライバー。Real-ESRGANのGPU処理とFFmpegのハードウェアエンコードを端末ごとに確認する |

`flutter doctor -v`、`git --version`、`python --version`、`pwsh --version` を実行し、同じターミナルから各ツールを呼び出せることを確認する。GitHubへのpush認証はWindows 2のGit Credential Manager等で設定する。更新確認は公開Releaseを使用する。Windowsのローカルビルドに秘密値は不要。CIは `UPDATE_REPOSITORY` とGitHubが提供する `GH_TOKEN` を使う。macOSの署名・公証設定は [既存の手順](macOS正式署名と公証.md) にある。

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

最初は候補の同梱フォルダから `Media Scaler.exe` を起動する。Windows 2で受け入れ確認が済んだ候補は、Gitルートから次のコマンドで完成アプリ領域に配置できる。既存の同版フォルダは保護される。

```powershell
python -B scripts/manage_windows.py run --purpose 'Place accepted Windows build' --defer -- pwsh -NoProfile -File scripts/promote_local_windows.ps1 -Version $version
python -B scripts/manage_windows.py finish --outcome success --task-id MediaScalerWindows2Acceptance
```

受け入れ途中では `--outcome incomplete` を指定する。旧版の資料や失敗調査中の出力は、共通清掃の保持記録に従う。

## Git外のファイルとデータ

| 内容 | 取得元・配置 | 受け渡し |
|---|---|---|
| Real-ESRGAN Vulkanエンジンとモデル | [v0.2.5.0 Windowsアーカイブ](https://github.com/xinntao/Real-ESRGAN/releases/tag/v0.2.5.0) の20220424版。`prepare_tools.py` で `tools/ai/windows/` と `models/` に展開 | 開発に必要。再取得可能 |
| FFmpeg、FFprobe、ライセンス | [BtbN FFmpeg Builds](https://github.com/BtbN/FFmpeg-Builds) のGPL Win64 n8.1系。`prepare_tools.py` で `tools/ffmpeg/windows/` に取得。latestの中身は更新されるため、取得時の `PROVENANCE.json` を確認 | 開発に必要。再取得可能 |
| AI実行環境 | [Python 3.13.15 Windows埋め込み版](https://www.python.org/ftp/python/3.13.15/python-3.13.15-embed-amd64.zip) とPyPIのncnn 1.0.20260526、NumPy 2.5.3、Pillow 12.3.0。`build_worker.py` で `tools/ai/windows/python/` に構成 | 開発に必要。再取得可能 |
| 端末固有設定・履歴・変換出力 | `%APPDATA%\com.example\media_scaler` の `shared_preferences.json` と `logs/`。変換出力はユーザーが選んだフォルダ。独立した履歴DBは現行実装で確認されていない | 開発再開には不要。設定を引き継ぐ場合は、両端末でアプリを終了し、Windows 2側をバックアップしてから設定JSONだけを選択移行。保存先の絶対パスはWindows 2で再選択する |
| アイコン原本、旧版、Windows 1の復旧記録 | アイコン原本はユーザーデータ領域。アプリに必要なアイコンはGitにある。旧版は完成アプリ領域。復旧資料は開発環境の `logs/` と `旧開発環境/` | Windows 1で保管。必要になったファイルだけ既存共有経由でSHA-256を照合しコピー |

アーカイブ・展開モデルのサイズとハッシュは、受け渡し用の `dependencies.json` を参照する。これはWindows 1で再取得した時点の値。Windows 1の環境変数やドライブ割り当て、認証・清掃台帳はWindows 2上で個別に確認する。共通ツールの配置先は端末の `CODEX_HOME` に従う。

## 受け入れ順と復旧

1. Windows 2で取得SHA、3フォルダ名、`context` の出力を照合する。
2. 依存復元とWindowsビルドを実施し、`Media Scaler` のウィンドウ名、ファイルの追加・削除、保存先とファイル名設定、再起動後の設定保持を確認する。
3. 短い合成画像・動画で通常変換、CPU画像AI、Vulkan動画AIを試し、出力を確認する。更新確認と清掃のドライランも確認する。
4. 必要なら検証済みインストーラーで上書き導入し、ショートカットと設定継承を確認する。その結果を記録してWindows 2への切り替えを確定する。

主要機能は画像・動画の拡縮、AI高画質化、GPU処理とCPUフォールバック、設定・出力名選択、更新通知。Windows 1の現行パスではFlutterテスト19件とRelease確認12件に合格した。候補の起動時にウィンドウ名を確認し、短い動画のH.264／H.265、CPU画像AI、Vulkan動画AI、既存設定の読み込み、公開Releaseの取得を検証した。Windows 2のGUI操作、GPUドライバー、インストールと再起動後の保存は受け入れ待ち。長時間変換は今回の引き継ぎ判定に含めていない。

Windows 1は既存のインストール先と完成アプリにある版から起動できる。必要に応じてアプリを終了し、設定を退避してから開発環境の `logs/backup-appdata/` と照合する。前回の復旧資料は `logs/Media Scaler Windows 1 移行記録.txt`。フォルダ名変更前の清掃台帳には旧パスが記録されているため、現行パスの登録とは別に保全する。
