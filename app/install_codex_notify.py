#!/usr/bin/env python3
"""Install/restore only Codex's user-level notify key; preserve the existing callback."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import tomllib

PROJECT = Path(__file__).resolve().parent


def replace_notify(text, command):
    """Replace one complete top-level TOML value without rewriting other settings."""
    parsed = tomllib.loads(text)
    lines = text.splitlines(keepends=True)
    end = next((i for i, line in enumerate(lines) if re.match(r"\s*\[", line)), len(lines))
    start = next((i for i in range(end) if re.match(r"^\s*notify\s*=", lines[i])), None)
    replacement = "" if command is None else "notify = " + json.dumps(command, ensure_ascii=False) + "\n"
    if start is None:
        if "notify" in parsed:
            raise ValueError("Unsupported notify syntax; configuration was not modified")
        updated = replacement + text
    else:
        stop = start + 1
        while stop <= len(lines):
            try:
                snippet = tomllib.loads("".join(lines[start:stop]))
                if "notify" in snippet:
                    break
            except tomllib.TOMLDecodeError:
                pass
            stop += 1
        if stop > len(lines):
            raise ValueError("Cannot safely locate notify value")
        updated = "".join(lines[:start]) + replacement + "".join(lines[stop:])
    after = tomllib.loads(updated)
    before_other = {k: v for k, v in parsed.items() if k != "notify"}
    after_other = {k: v for k, v in after.items() if k != "notify"}
    if before_other != after_other or after.get("notify") != command:
        raise ValueError("Configuration validation failed")
    return updated


def atomic_write(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        staging = Path(temporary.name)
        temporary.write(data)
        temporary.flush()
        os.fsync(temporary.fileno())
    try:
        staging.chmod(mode)
        staging.replace(path)
    finally:
        if staging.exists():
            staging.unlink()


def locations():
    codex = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    folder = codex / "elaina-notifier"
    app = Path.home() / "Applications/Elaina.app"
    bridge = folder / "bridge.json"
    command = [str(app / "Contents/MacOS/elaina-notify"), "--config", str(bridge), "--codex"]
    return codex / "config.toml", folder, app, bridge, command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["preview", "install", "restore"])
    args = parser.parse_args()
    config, folder, app, bridge, command = locations()
    old_text = config.read_text() if config.exists() else ""
    parsed = tomllib.loads(old_text)
    old_notify = parsed.get("notify")
    manifest_path = folder / "installation.json"
    if args.mode == "restore":
        manifest = json.loads(manifest_path.read_text())
        if old_notify != command:
            raise ValueError("notify has changed since installation; refusing to overwrite it")
        updated = replace_notify(old_text, manifest["previousNotify"])
        atomic_write(config, updated.encode(), config.stat().st_mode & 0o777)
        print("已還原原本的 notify 設定；伊蕾娜程式與台詞檔案仍保留。請重新開啟 ChatGPT 桌面程式。")
        return
    if old_notify == command:
        original = json.loads(bridge.read_text())["originalNotify"]
        previous = json.loads(manifest_path.read_text())["previousNotify"]
    else:
        original = old_notify or []
        previous = old_notify
    if not isinstance(original, list) or not all(isinstance(arg, str) for arg in original):
        raise ValueError("notify must be an array of strings")
    updated = replace_notify(old_text, command)
    plan = {"app": str(app), "config": str(config), "preservedNotify": original,
            "newNotify": command, "dialogues": str(Path.home() / "Library/Application Support/ElainaDesktopPet/dialogues.json")}
    if args.mode == "preview":
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return
    source = PROJECT / "Elaina.app"
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(source)], check=True)
    if app.exists():
        identity = plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier")
        if identity != "local.elaina.desktop-pet":
            raise ValueError("An unrelated Elaina.app exists; refusing to replace it")
    folder.mkdir(parents=True, exist_ok=True)
    app.parent.mkdir(parents=True, exist_ok=True)
    # Prepare the full app before changing the active configuration.
    staging = Path(tempfile.mkdtemp(prefix="elaina-install-", dir=app.parent)) / "Elaina.app"
    try:
        shutil.copytree(source, staging)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staging)], check=True)
        if (config.read_text() if config.exists() else "") != old_text:
            raise ValueError("Configuration changed during installation; retry")
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        atomic_write(folder / ("config-before-" + stamp + ".toml"), old_text.encode())
        if app.exists():
            app.rename(folder / ("Elaina-before-" + stamp + ".app"))
        staging.rename(app)
        setting = {"originalNotify": original, "appPath": str(app), "statusPath": str(folder / "last-event.json")}
        atomic_write(bridge, json.dumps(setting, ensure_ascii=False, indent=2).encode())
        subprocess.run([str(app / "Contents/MacOS/Elaina"), "--self-test"], check=True)
        subprocess.run(["/usr/bin/open", "-g", "-n", str(app), "--args", "--replace-running"], check=True)
        subprocess.run([os.sys.executable, str(PROJECT / "Tests/test_live_notify.py")], check=True)
        if (config.read_text() if config.exists() else "") != old_text:
            raise ValueError("Configuration changed during verification; no configuration was overwritten")
        atomic_write(manifest_path, json.dumps({"previousNotify": previous, "notify": command}, ensure_ascii=False, indent=2).encode())
        atomic_write(config, updated.encode(), config.stat().st_mode & 0o777 if config.exists() else 0o600)
    finally:
        shutil.rmtree(staging.parent, ignore_errors=True)
    print("已安裝伊蕾娜 1.1 並連接 Codex notify；原本的通知程式已保留。")
    print("請在這次工作結束後重新開啟 ChatGPT 桌面程式，讓新設定生效。")


if __name__ == "__main__":
    main()
