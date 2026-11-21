# Media Scaler

- Media Scaler の主開発端末は Windows 2。受け入れまでは Windows 1 の稼働版・ソース・データを復旧元として保持する。[引き継ぎ手順](docs/Windows2引き継ぎ.md)を参照する。
- `開発環境-(ソースコード・テスト・検証ログ )` が Flutter の Git ルート。既存の `lib/`、`test/`、`windows/`、`macos/` を使う。
- Windows 2 では開発ルート内の `tools/sdk/python/python.exe` から管理コマンドを実行できる。Flutter、Python、Inno Setup、AI ツールと依存キャッシュは次回の開発・ビルドにも使う。
- Windows では `python -B scripts/manage_windows.py context` で割り当てを確認する。必要に応じて `setup` で対応表を更新する。同じ入口で `test --defer`、`build --version <版> --defer`、`run` を実行する。検証済みの候補は `run` から `scripts/promote_local_windows.ps1 -Version <版>` を使い、`完成アプリ-(正式ビルド・配布ファイル)` へ配置する。
- 開発依頼ごとに、終了前に同じ入口で `finish --outcome <success|incomplete|failed> --task-id <英数字の作業名>` を実行する。追加の検証出力は `run --output <ファイル名> --defer` で登録し、処分可能になった実行の出力を片付ける。証跡と容量は `logs/` に保存する。
- 管理対象の候補版・完成版は同梱の `runtime.json` を使い、設定・稼働ログを `ユーザーデータ-(設定・履歴・データベース)` に保存する。公開インストーラーから導入した版は既存の OS 標準パスを使う。
- GitHub は `skybluema891-dev/media-scaler`。既存タグ、インストール ID、公開インストーラーのファイル名、更新先を維持する。
- `logs/` と `旧開発環境/` は端末内保全用。ユーザーデータ、SDK、モデル、検証出力、配布バイナリを Git に含めない。
