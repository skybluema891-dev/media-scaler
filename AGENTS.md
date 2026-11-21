# Media Scaler

- Flutter の Git ルートはこのフォルダ。既存の `lib/`、`test/`、`windows/`、`macos/` を使う。
- Windows では共通 manager の `test --defer` と `build --defer` を使用する。`build/candidate` で検証した版は manager の `run` から `scripts/promote_local_windows.ps1 -Version <版>` を実行して `完成アプリ` へ配置する。
- Windows の設定・ログは OS 標準の `%APPDATA%\com.example\media_scaler` を引き継ぐ。管理ツールの既定データパスはアプリ実行時の設定パスに使わない。`ユーザーデータ` にはプロジェクト内の原本やユーザーが選んだ出力だけを置く。
- GitHub は `skybluema891-dev/media-scaler`。既存タグ、インストール ID、公開インストーラーのファイル名、更新先を維持する。
- `logs/` と `旧開発環境/` は端末内保全用。ユーザーデータ、SDK、モデル、検証出力、配布バイナリを Git に含めない。
