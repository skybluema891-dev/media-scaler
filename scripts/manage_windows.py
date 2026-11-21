"""Use common-apps with the existing Media Scaler directories on Windows."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import NamedTemporaryFile

PROJECT = Path(__file__).absolute().parents[1]
APP_ROOT = PROJECT.parent
TEMPLATE = PROJECT / "config" / "app-layout.windows.json"
ORIGIN = "https://github.com/skybluema891-dev/media-scaler.git"
SHORT_AREAS = {
    "development": "開発環境",
    "release": "完成アプリ",
    "user_data": "ユーザーデータ",
}
COMMANDS = {"setup", "context", "paths", "route", "test", "build", "run", "finish"}


def common_manager():
    home = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
    path = home / "common-apps" / "manager.py"
    if not path.is_file():
        raise ValueError("共通ルールの common-apps/manager.py を導入してください。")
    spec = importlib.util.spec_from_file_location("common_app_manager", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def setup(manager, expected):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(PROJECT), *args],
                                       encoding="utf-8").strip()

    if Path(git("rev-parse", "--show-toplevel")) != PROJECT or git(
        "remote", "get-url", "origin"
    ) != ORIGIN:
        raise ValueError("既存の Media Scaler Git リポジトリを確認してください。")

    manifest = APP_ROOT / manager.MANIFEST
    legacy = expected | {"areas": SHORT_AREAS}
    previous = None
    if manifest.exists() or manifest.is_symlink():
        if manifest.is_symlink() or getattr(manifest.lstat(), "st_file_attributes", 0) & 0x400:
            raise ValueError("対応表はローカルの通常ファイルにしてください。")
        previous = manifest.read_text(encoding="utf-8")
        if json.loads(previous) not in (expected, legacy):
            raise ValueError("未知の既存対応表を保護しました。")

    for role, name in expected["areas"].items():
        target = APP_ROOT / name
        if not target.exists():
            short = SHORT_AREAS[role]
            if any(entry.name == short or entry.name.startswith(short + "-")
                   for entry in APP_ROOT.iterdir()):
                raise ValueError(f"同じ用途の既存フォルダを確認してください: {name}")
        manager.safe_directory(target, create=True)
    for local_dir in ("logs", ".verification"):
        manager.safe_directory(PROJECT / local_dir, create=True)

    if previous is not None and json.loads(previous) == legacy:
        backup = PROJECT / "logs" / "app-layout.before-windows2.json"
        if not backup.exists():
            manager.write_new(backup, previous)
        elif backup.is_symlink() or backup.read_text(encoding="utf-8") != previous:
            raise ValueError("既存の対応表バックアップを確認してください。")

    if previous is None:
        manager.write_new(manifest, manager.json_text(expected))
    elif json.loads(previous) != expected:
        with NamedTemporaryFile(mode="w", dir=APP_ROOT, prefix=".app-layout-",
                                encoding="utf-8", delete=False) as staged:
            staged.write(manager.json_text(expected))
        os.replace(staged.name, manifest)


def main():
    arguments = sys.argv[1:]
    if not arguments or arguments[0] not in COMMANDS:
        raise ValueError("使用法: manage_windows.py " + "|".join(sorted(COMMANDS)))
    action = arguments[0]
    options = arguments[:arguments.index("--")] if "--" in arguments else arguments
    if any(arg.split("=")[0] in {"--root", "--project"} for arg in options):
        raise ValueError("対象はこの Media Scaler の作業場所から解決します。")
    if action == "setup" and len(arguments) != 1:
        raise ValueError("setup は引数を取りません。")

    manager = common_manager()
    manager.safe_directory(PROJECT)
    expected = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    if PROJECT.name != expected["areas"]["development"]:
        raise ValueError(f"開発環境の実フォルダ名を確認してください: {PROJECT.name}")
    if action == "setup":
        setup(manager, expected)

    # The current common manager validates schema 3 against its role labels.
    # Bind the Media Scaler labels in this invocation only.
    manager.ROLES = expected["areas"]
    _, actual = manager.load(APP_ROOT)
    if actual != expected:
        raise ValueError("Media Scaler の対応表と一致しません。setup を確認してください。")
    if any(not (APP_ROOT / name).is_dir() for name in manager.ROLES.values()):
        raise ValueError("3フォルダの実体を確認してください。")
    os.chdir(PROJECT)
    if action == "setup":
        sys.argv[1:] = ["context"]
    return manager.main()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Media Scaler: {error}", file=sys.stderr)
        sys.exit(1)
