"""Installer composition with external service-manager and Codex fixtures."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
MANAGER = r'''#!/usr/bin/env python3
import json, os, pathlib, plistlib, signal, subprocess, sys
home = pathlib.Path(os.environ["HOME"])
store = home / "manager"
args = sys.argv[1:]
is_mac = pathlib.Path(sys.argv[0]).name == "launchctl"
if is_mac:
    operation = args[0]
    target = args[-1]
    profile = target.split(".")[-1]
    if operation == "print" and target.count("/") == 1:
        raise SystemExit(113 if (store / "manager-down").exists() else 0)
    if operation == "print-disabled":
        for disabled in store.glob("*.disabled"):
            print('"dev.niels.codex-shared.' + disabled.stem + '" => disabled')
        raise SystemExit(0)
    if operation == "bootstrap": profile = pathlib.Path(target).stem.split(".")[-1]
else:
    args = args[1:]
    operation = args[0]
    if operation in ("show-environment", "daemon-reload"):
        raise SystemExit(1 if (store / "manager-down").exists() else 0)
    profile = args[-1].split("@")[1].split(".")[0]
state = store / profile
enabled = store / (profile + ".enabled")
if operation in ("print", "is-active"):
    if state.exists():
        print("\tstate = running" if is_mac else "active")
        raise SystemExit(0)
    if not is_mac: print("inactive")
    raise SystemExit(113 if is_mac else 3)
if operation == "is-enabled": raise SystemExit(0 if enabled.exists() else 1)
with (store / "calls").open("a") as stream: stream.write(operation + " " + profile + "\n")
if operation == "enable":
    enabled.touch()
    (store / (profile + ".disabled")).unlink(missing_ok=True)
elif operation in ("bootstrap", "kickstart", "start"):
    if (store / (profile + ".disabled")).exists(): raise SystemExit(5)
    if is_mac:
        unit = home / "Library/LaunchAgents" / ("dev.niels.codex-shared." + profile + ".plist")
        command = plistlib.loads(unit.read_bytes())["ProgramArguments"]
    else:
        unit = home / ".config/systemd/user" / ("codex-shared@" + profile + ".service")
        command = next(line[10:].split() for line in unit.read_text().splitlines() if line.startswith("ExecStart="))
        command = [arg.replace("%h", str(home)) for arg in command]
    # The native interpreter path is an external platform dependency.
    command[0] = sys.executable
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    state.write_text(str(child.pid))
elif operation in ("stop", "bootout"):
    if state.exists():
        try: os.kill(int(state.read_text()), signal.SIGTERM)
        except ProcessLookupError: pass
        state.unlink()
else:
    raise SystemExit("unexpected fixture operation")
'''

CODEX = r'''#!/usr/bin/env python3
import os, pathlib, signal, socket, sys
if sys.argv[1:] == ["--version"]:
    print("codex-cli 0.153.4")
    raise SystemExit(0)
if "app-server" not in sys.argv: raise SystemExit(65)
path = pathlib.Path(sys.argv[-1][7:])
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
path.unlink(missing_ok=True)
with socket.socket(socket.AF_UNIX) as listener:
    listener.bind(str(path))
    path.chmod(0o600)
    listener.listen()
    while True:
        connection, _ = listener.accept()
        connection.close()
'''


class Services(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="codex-services-", dir="/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.assets = self.root / "assets"
        shutil.copytree(REPO / "assets", self.assets)
        self.manager = self.home / "manager"
        self.manager.mkdir()
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        for name in ("launchctl", "systemctl"):
            executable = fake_bin / name
            executable.write_text(MANAGER)
            executable.chmod(0o755)
        raw = self.home / ".local/bin/codex"
        raw.parent.mkdir(parents=True)
        raw.write_text(CODEX)
        raw.chmod(0o755)
        manifest = self.home / ".local/lib/node_modules/@openai/codex/package.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text('{"name":"@openai/codex","version":"0.153.4"}')
        for account in (".codex", ".codex-work", ".codex-work2"):
            (self.home / account).mkdir(mode=0o700)
        self.env = {**os.environ, "HOME": str(self.home),
                    "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]}
        self.addCleanup(self.stop_children)

    def stop_children(self):
        for profile in ("personal", "work", "work2"):
            state = self.manager / profile
            if state.exists():
                try:
                    os.kill(int(state.read_text()), signal.SIGTERM)
                except ProcessLookupError:
                    pass
                state.unlink()

    def apply(self, host, restart="0"):
        script = '''set -euo pipefail
source "$1/lib/common.sh"
source "$1/lib/ai-tools.sh"
dev_server_home_dir="$HOME"
dev_server_assets_root="$2"
dev_server_ai_host="$3"
source "$1/lib/codex-services.sh"
trap codex_services_cleanup EXIT
codex_services_preflight "$3" "$4"
codex_services_install
ai_install_dirs
ai_install_profiles
codex_services_activate
'''
        return subprocess.run(["bash", "-c", script, "fixture", str(REPO),
                               str(self.assets), host, restart], env=self.env,
                              capture_output=True, text=True, timeout=40)

    def pids(self):
        return {profile: (self.manager / profile).read_text()
                for profile in ("personal", "work", "work2")
                if (self.manager / profile).exists()}

    def test_first_apply_starts_three_and_second_apply_is_quiescent(self):
        for host in ("macbook", "arch"):
            with self.subTest(host=host):
                first = self.apply(host)
                self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
                before = self.pids()
                self.assertEqual(set(before), {"personal", "work", "work2"},
                                 "apply must start each account's shared server")
                calls = (self.manager / "calls").read_bytes()
                marker = self.home / ".local/state/dev-server/active/codex.runtime.sha256"
                marker_inode = marker.stat().st_ino
                second = self.apply(host)
                self.assertEqual(second.returncode, 0, second.stderr + second.stdout)
                self.assertEqual(self.pids(), before)
                self.assertEqual((self.manager / "calls").read_bytes(), calls)
                self.assertEqual(marker.stat().st_ino, marker_inode)
                self.assertEqual(second.stdout, "")
                self.stop_children()

    def test_changed_live_inputs_require_restart_before_any_replacement(self):
        first = self.apply("arch")
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        installed = self.home / ".local/libexec/codex-shared"
        self.assertTrue(installed.exists(), "apply must install its host-owned helper")
        before = installed.read_bytes()
        pids = self.pids()
        helper = self.assets / "codex/codex-shared.py"
        helper.write_bytes(helper.read_bytes() + b"\n# Changed declared helper.\n")
        refused = self.apply("arch")
        self.assertEqual(refused.returncode, 2, refused.stderr + refused.stdout)
        self.assertIn("ACTION", refused.stdout)
        self.assertEqual(installed.read_bytes(), before)
        self.assertEqual(self.pids(), pids)
        accepted = self.apply("arch", "1")
        self.assertEqual(accepted.returncode, 0, accepted.stderr + accepted.stdout)
        self.assertNotEqual(installed.read_bytes(), before)
        self.assertTrue(all(self.pids()[key] != pid for key, pid in pids.items()))

    def test_disabled_mac_service_is_enabled_and_missing_manager_requires_login(self):
        disabled = self.manager / "work.disabled"
        disabled.touch()
        down = self.manager / "manager-down"
        down.touch()
        unavailable = self.apply("macbook")
        self.assertEqual(unavailable.returncode, 2, unavailable.stderr + unavailable.stdout)
        self.assertFalse((self.home / ".local/libexec/codex-shared").exists())
        down.unlink()
        ready = self.apply("macbook")
        self.assertEqual(ready.returncode, 0, ready.stderr + ready.stdout)
        self.assertFalse(disabled.exists())
        self.assertEqual(set(self.pids()), {"personal", "work", "work2"})

    def test_failed_start_has_no_activation_proof_and_rerun_recovers(self):
        raw = self.home / ".local/bin/codex"
        raw.write_text(CODEX.replace('if "app-server" not in sys.argv:',
                                    'if os.environ["CODEX_HOME"].endswith(".codex-work"):'))
        failed = self.apply("arch")
        self.assertNotEqual(failed.returncode, 0, "failed servers must fail apply")
        marker = self.home / ".local/state/dev-server/active/codex.runtime.sha256"
        self.assertFalse(marker.exists())
        partial = self.pids()
        refused = self.apply("arch")
        self.assertEqual(refused.returncode, 2, refused.stderr + refused.stdout)
        self.assertEqual(self.pids(), partial)
        raw.write_text(CODEX)
        recovered = self.apply("arch", "1")
        self.assertEqual(recovered.returncode, 0, recovered.stderr + recovered.stdout)
        self.assertTrue(marker.exists())
        before = self.pids()
        os.kill(int(before["work"]), signal.SIGTERM)
        (self.manager / "work").unlink()
        rerun = self.apply("arch")
        self.assertEqual(rerun.returncode, 0, rerun.stderr + rerun.stdout)
        self.assertEqual(self.pids()["personal"], before["personal"])
        self.assertEqual(self.pids()["work2"], before["work2"])
        self.assertNotEqual(self.pids()["work"], before["work"])


if __name__ == "__main__":
    unittest.main()
