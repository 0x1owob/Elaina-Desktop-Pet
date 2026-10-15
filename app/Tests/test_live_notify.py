"""Actual project-app IPC test, isolated from the installed pet and its preferences.

Requires a GUI login session. Never installs a hook or launches ~/Applications/Elaina.app.
--external attaches to a GUI-launched test copy carrying the three isolation env settings.
Fullscreen commands exercise controller logic, not real application detection.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("--app", type=Path, default=Path(__file__).resolve().parents[1] / "Elaina.app")
parser.add_argument("--external", action="store_true")
args = parser.parse_args()
app = args.app.resolve()
if app == (Path.home() / "Applications/Elaina.app").resolve():
    parser.error("Use the project app or an isolated temporary test copy, never the installed app")
binary = app / "Contents/MacOS/Elaina"
helper = app / "Contents/MacOS/elaina-notify"

with tempfile.TemporaryDirectory(prefix="elaina-el002-ipc-") as temporary:
    root = Path(temporary)
    namespace = "local.elaina.tests." + uuid.uuid4().hex
    environment = dict(os.environ)
    if args.external:
        for key in ["ELAINA_IPC_CHANNEL", "ELAINA_DEFAULTS_SUITE", "ELAINA_DATA_DIR"]:
            if not environment.get(key):
                parser.error("--external needs all three ELAINA isolation environment values")
    else:
        environment.update(ELAINA_IPC_CHANNEL=namespace, ELAINA_DEFAULTS_SUITE=namespace,
                           ELAINA_DATA_DIR=str(root / "dialogues"))
    original = root / "original.py"
    captured = root / "captured.json"
    status = root / "status.json"
    original.write_text("import pathlib,sys\npathlib.Path(sys.argv[1]).write_text(sys.argv[2])\n")
    config = root / "bridge.json"
    config.write_text(json.dumps({"originalNotify": ["/usr/bin/python3", str(original), str(captured)],
                                  "appPath": str(app), "statusPath": str(status)}))
    process = None

    def control(command):
        result = subprocess.run([str(helper), "--test-control", command], env=environment,
                                capture_output=True, text=True, timeout=8, check=True)
        response = json.loads(result.stdout)
        assert response.get("result") != "timeout", response
        return response

    def send(event):
        raw = json.dumps(event, ensure_ascii=False)
        result = subprocess.run([str(helper), "--config", str(config), "--codex", raw], env=environment,
                                check=True, capture_output=True, text=True, timeout=12)
        assert captured.read_text() == raw, "existing notifier did not receive the exact payload"
        assert "privacy-sentinel" not in status.read_text(), "conversation text leaked into metadata"
        return json.loads(result.stdout)

    def event():
        return {"type": "agent-turn-complete", "thread-id": "elaina-el002-test",
                "turn-id": str(uuid.uuid4()), "status": "completed",
                "last-assistant-message": "privacy-sentinel-魔女 `literal` $literal",
                "input-messages": ["privacy-sentinel-user-message"]}

    try:
        if not args.external:
            process = subprocess.Popen([str(binary), "--start-paused"], env=environment,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        initial = control("state")
        if not initial["screens"]:
            raise RuntimeError("GUI screens are unavailable; actual IPC/GUI validation is blocked")
        if not args.external:
            assert initial["firstGreetingIssued"] is True, initial
        control("dismiss")
        control("resume")
        base = event()
        response = send(base)
        assert response["result"] == "reacted" and response["bubbleVisible"] is False, response
        assert response["reactionActive"] is True and "message" not in response, response
        assert send(base)["result"] == "duplicate"
        for value in ["failed", "interrupted", "waiting_for_approval"]:
            assert send(dict(base, status=value))["result"] == "ignored"
        assert send(dict(base, type="approval-requested"))["result"] == "ignored"
        print("PASS actual IPC: silent reaction, retry deduplication, status/type filtering, exact notifier forwarding")

        control("pause")
        assert send(event())["result"] == "suppressed"
        control("resume")
        assert control("greet")["bubbleVisible"] is True
        control("dismiss")
        assert control("jump")["jumping"] is True
        control("pause")
        control("dismiss")
        home = control("state")
        control("fullscreen-on")
        time.sleep(1.3)
        away = control("state")
        assert away["phase"] == "away" and away["panelVisible"] is False and away["bubbleVisible"] is False
        assert control("greet")["bubbleVisible"] is False
        assert control("jump")["jumping"] is False
        suppressed = event()
        assert send(suppressed)["result"] == "suppressed"
        assert control("show")["panelVisible"] is False
        control("fullscreen-off")
        time.sleep(1.3)
        returned = control("state")
        assert returned["phase"] == "home" and returned["bubbleVisible"] is False, returned
        assert abs(returned["x"] - home["x"]) < 0.01 and abs(returned["y"] - home["y"]) < 0.01
        assert send(suppressed)["result"] == "duplicate"
        control("fullscreen-on")
        control("fullscreen-off")
        control("fullscreen-on")
        time.sleep(1.3)
        control("hide")
        control("fullscreen-off")
        time.sleep(1.3)
        hidden = control("state")
        assert hidden["manuallyHidden"] is True and hidden["panelVisible"] is False
        control("unhide")
        control("dismiss")
        print("PASS controller IPC: interaction, pause suppression, rapid fullscreen switches, exact return, manual hide priority")
        print("NOTE fullscreen was simulated; real App and browser fullscreen detection remains a separate manual check")

        if not args.external:
            control("quit")
            process.wait(timeout=5)
            process = subprocess.Popen([str(binary), "--start-paused"], env=environment,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            restarted = control("state")
            assert restarted["firstGreetingIssued"] is False and restarted["bubbleVisible"] is False
            print("PASS actual app relaunch retains the greeting-once preference without speaking")
    finally:
        try:
            control("clear-defaults")
            control("quit")
        except (subprocess.SubprocessError, AssertionError, json.JSONDecodeError):
            pass
        if process is not None:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
