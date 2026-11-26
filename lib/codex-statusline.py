"""Apply the same Codex footer to each matching fleet account."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tomllib


def request(server, message):
    server.stdin.write(json.dumps(message) + "\n")
    server.stdin.flush()
    if "id" not in message:
        return
    for line in server.stdout:
        reply = json.loads(line)
        if reply.get("id") == message["id"]:
            if "error" in reply:
                raise ValueError(f"codex rejected {message['method']}")
            return reply["result"]
    raise ValueError("codex exited before confirming the config change")


def configure(binary, account):
    fields = ["model-with-reasoning", "current-dir", "context-used"]
    if account.name == ".codex-work":
        fields.append("five-hour-limit")
    fields.append("weekly-limit")
    settings = {"status_line": fields, "status_line_use_colors": True}
    config = account / "config.toml"
    if config.is_symlink() or account.is_symlink() or (config.exists() and not config.is_file()):
        raise ValueError(f"expected a regular codex configuration in {account}")

    def matches():
        if not config.exists():
            return False
        with config.open("rb") as stream:
            tui = tomllib.load(stream).get("tui", {})
        return (isinstance(tui, dict) and tui.get("status_line") == fields
                and tui.get("status_line_use_colors") is True)

    if matches():
        return False
    # Codex edits its own TOML, preserving other keys, comments and profile state.
    with subprocess.Popen(
        [binary, "app-server", "--listen", "stdio://"], cwd="/",
        env={**os.environ, "CODEX_HOME": str(account)}, stdin=subprocess.PIPE,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    ) as server:
        try:
            signal.alarm(30)
            request(server, {"id": 1, "method": "initialize", "params": {
                "clientInfo": {"name": "dev-server", "version": "1"}}})
            request(server, {"method": "initialized"})
            edits = [{"keyPath": "tui." + key, "value": value, "mergeStrategy": "replace"}
                     for key, value in settings.items()]
            result = request(server, {"id": 2, "method": "config/batchWrite",
                                      "params": {"edits": edits}})
            if result.get("status") != "ok" or not matches():
                raise ValueError(f"could not verify the codex footer in {account}")
        finally:
            signal.alarm(0)
            server.stdin.close()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
    return True


def timeout(signum, frame):
    raise TimeoutError("codex timed out writing its configuration")


if __name__ == "__main__":
    signal.signal(signal.SIGALRM, timeout)
    home = Path(sys.argv[1])
    for profile in (".codex", ".codex-work", ".codex-work2"):
        try:
            changed = configure(home / ".local/bin/codex", home / profile)
        except (OSError, ValueError, KeyError) as error:
            sys.exit(f"{profile} status line: {error}")
        print(f"{'CHANGED' if changed else 'UP TO DATE'}  {profile} status line")
