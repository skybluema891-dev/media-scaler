# Media Scaler

- Media Scaler の主開発端末は Windows 2。受け入れまでは Windows 1 の稼働版・ソース・データを復旧元として保持する。[引き継ぎ手順](docs/Windows2引き継ぎ.md)を参照する。
- `開発環境-(ソースコード・テスト・検証ログ )` が Flutter の Git ルート。既存の `lib/`、`test/`、`windows/`、`macos/` を使う。
- Windows では `python -B scripts/manage_windows.py context` で共通 manager の割り当てを確認する。同じ入口で `test --defer`、`build --version <版> --defer`、`finish` を実行する。検証済みの候補は `run` から `scripts/promote_local_windows.ps1 -Version <版>` を使い、`完成アプリ-(正式ビルド・配布ファイル)` へ配置する。
- Windows の設定・ログは OS 標準の `%APPDATA%\com.example\media_scaler`。管理用の `ユーザーデータ-(設定・履歴・データベース)` にはプロジェクト内の原本やユーザーが選んだ出力を置く。
- GitHub は `skybluema891-dev/media-scaler`。既存タグ、インストール ID、公開インストーラーのファイル名、更新先を維持する。
- `logs/` と `旧開発環境/` は端末内保全用。ユーザーデータ、SDK、モデル、検証出力、配布バイナリを Git に含めない。
