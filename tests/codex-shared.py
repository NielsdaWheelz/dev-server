"""Host boundary fixtures, not Linux/systemd/tmux/provider qualification."""

import grp
import importlib.util
import json
import os
from pathlib import Path
import pwd
import socket
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
HOST = REPO / "assets/codex/codex-shared.py"
spec = importlib.util.spec_from_file_location("codex_host", HOST)
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)

FAKE = '''#!/usr/bin/env python3
import json, os, pathlib, sys
path = pathlib.Path(__file__)
args = sys.argv[1:]
if path.name == "codex" and args == ["--version"]:
    raise SystemExit("server and terminal admission must not probe a version")
if path.name == "codex" and args == ["--help"]:
    print("native fixture help")
    raise SystemExit(0)
if path.name == "codex" and args == ["--unsupported"]:
    print("native fixture argument error", file=sys.stderr)
    raise SystemExit(23)
with path.with_suffix(".calls").open("a") as stream:
    stream.write(json.dumps({"argv": args, "env": dict(os.environ), "cwd": os.getcwd()}) + "\\n")
'''

class HostBoundary(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cdx-host-", dir="/tmp")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        os.chown(self.root, -1, os.getgid())
        self.work = self.root / "work ; $(not-a-command)"
        self.work.mkdir()
        self.config = json.loads((REPO / "assets/codex/profiles.json").read_text())
        account = pwd.getpwuid(os.getuid())
        self.config.update(development_user=account.pw_name, jarvis_user=account.pw_name,
                           client_group=grp.getgrgid(os.getgid()).gr_name,
                           binary=str(self.root / "codex"),
                           cognition_cwd_parent=str(self.root / "empty"))
        Path(self.config["cognition_cwd_parent"]).mkdir()
        for key, row in self.config["profiles"].items():
            directory = self.root / Path(row["account_home"]).name
            directory.mkdir(mode=0o700)
            row.update(account_home=str(directory), endpoint=f"unix://{directory}/server.sock")
        for command in ("codex",):
            target = self.root / command
            target.write_text(FAKE)
            target.chmod(0o755)
        self.config_path = self.root / "profiles.json"
        self.write_config()

    def write_config(self):
        self.config_path.write_text(json.dumps(self.config))
        self.config_path.chmod(0o600)

    def calls(self, command):
        path = self.root / f"{command}.calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_host(self, *args, cwd=None):
        return subprocess.run([sys.executable, str(HOST), "--config", str(self.config_path), *args],
                              cwd=cwd or self.work, capture_output=True, timeout=15,
                              env={**os.environ, "HOME": str(self.root), "TERM": "xterm-256color",
                                   "COLORTERM": "truecolor", "TMUX": "untrusted", "TMUX_PANE": "%99",
                                   "TMUX_TMPDIR": "/not-the-default", "OPENAI_API_KEY": "synthetic",
                                   "JARVIS_SECRET_FIXTURE": "synthetic"})

    def prepare_workstation(self):
        binary = self.root / ".local/bin/codex"
        binary.parent.mkdir(parents=True)
        binary.write_text(FAKE)
        binary.chmod(0o755)
        (self.root / ".local/share/codex-shared/empty").mkdir(parents=True, mode=0o700)

    def test_servers_use_exact_accounts_without_overriding_account_policy(self):
        self.prepare_workstation()
        for machine in ("devbox", "macbook", "arch"):
            for key, row in self.config["profiles"].items():
                with self.subTest(host=machine, profile=key):
                    workstation = machine != "devbox"
                    endpoint = (f"unix://{self.root}/.local/run/codex-shared/{key}/app-server.sock"
                                if workstation else row["endpoint"])
                    result = self.run_host("--host", machine, "server", key)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    call = self.calls(".local/bin/codex" if workstation else "codex")[-1]
                    self.assertEqual(call["argv"], ["app-server", "--listen", endpoint])
                    self.assertEqual(call["cwd"], str(self.root / ".local/share/codex-shared/empty")
                                     if workstation else self.config["cognition_cwd_parent"])
                    self.assertEqual(call["env"]["CODEX_HOME"], row["account_home"])
                    self.assertEqual(call["env"]["TERM"], "dumb")
                    self.assertNotIn("COLORTERM", call["env"])
                    if machine == "macbook":
                        self.assertIn("/opt/homebrew/bin", call["env"]["PATH"].split(":"))
                    for field in ("TMUX", "TMUX_PANE", "TMUX_TMPDIR", "OPENAI_API_KEY", "JARVIS_SECRET_FIXTURE"):
                        self.assertNotIn(field, call["env"])

    def test_workstation_rejects_jarvis_privileged_modes_before_effects(self):
        self.prepare_workstation()
        for machine in ("macbook", "arch"):
            for arguments in (("terminal",), ("grant-socket", "personal")):
                with self.subTest(host=machine, arguments=arguments):
                    self.assertNotEqual(self.run_host("--host", machine, *arguments).returncode, 0)
        self.assertEqual(self.calls(".local/bin/codex"), [])
        self.assertEqual(self.calls("tmux"), [])

    def test_human_launchers_preserve_native_arguments_environment_cwd_and_exit(self):
        self.prepare_workstation()
        quoted_account = self.root / "personal ' $() ;"
        quoted_account.mkdir()
        self.config["profiles"]["personal"]["account_home"] = str(quoted_account)
        self.write_config()
        commands = self.root / "bin"
        commands.mkdir()
        env = {"PATH": os.environ["PATH"], "HOME": str(self.root / "different-home"),
               "CODEX_HOME": "overridden-by-account-selection", "TERM": "xterm-256color",
               "TMUX": "synthetic-tmux", "TMUX_PANE": "%99", "COLORTERM": "truecolor",
               "OPENAI_API_KEY": "synthetic", "USER_CONFIG_FIXTURE": "synthetic"}
        for machine in ("devbox", "macbook", "arch"):
            result = self.run_host("--host", machine, "launcher")
            self.assertEqual(result.returncode, 0, result.stderr)
            binary = "codex" if machine == "devbox" else ".local/bin/codex"
            for command, profile in host.COMMANDS.items():
                launcher = commands / command
                launcher.write_bytes(result.stdout)
                for arguments in ([], ["--yolo", "synthetic prompt ; $()"],
                                  ["-c", 'model_reasoning_effort="high"', "resume", "--last"],
                                  ["exec", "--json", "-"], ["login", "status"],
                                  ["--remote", "unix:///synthetic", "fork", "--last"]):
                    with self.subTest(host=machine, command=command, arguments=arguments):
                        child = subprocess.run(["bash", str(launcher), *arguments], cwd=self.root,
                                               env=env, capture_output=True, timeout=15)
                        self.assertEqual(child.returncode, 0, child.stderr)
                        call = self.calls(binary)[-1]
                        self.assertEqual(call["argv"], arguments)
                        self.assertEqual(call["cwd"], str(self.root))
                        for key, value in env.items():
                            self.assertEqual(call["env"][key], self.config["profiles"][profile]["account_home"]
                                             if key == "CODEX_HOME" else value)
                for arguments, status, stdout, stderr in (
                        (["--help"], 0, b"native fixture help\n", b""),
                        (["--unsupported"], 23, b"", b"native fixture argument error\n")):
                    child = subprocess.run(["bash", str(launcher), *arguments], cwd=self.root,
                                           env=env, capture_output=True, timeout=15)
                    self.assertEqual((child.returncode, child.stdout, child.stderr), (status, stdout, stderr))

    def test_native_discovery_connects_to_exact_listener_and_is_quiescent(self):
        links = []
        Path(self.config["profiles"]["work"]["account_home"]).chmod(0o750)
        Path(self.config["profiles"]["work2"]["account_home"]).chmod(0o2700)
        accounts = {Path(row["account_home"]): Path(row["account_home"]).stat()
                    for row in self.config["profiles"].values()}
        result = self.run_host("check-discovery")
        self.assertEqual(result.returncode, 0, result.stderr)
        for row in self.config["profiles"].values():
            self.assertFalse((Path(row["account_home"]) / "app-server-control").exists())
        result = self.run_host("install-discovery")
        self.assertEqual((result.returncode, result.stdout), (0, b"CHANGED codex.runtime\n"), result.stderr)
        for row in self.config["profiles"].values():
            link = Path(row["account_home"]) / "app-server-control/app-server-control.sock"
            self.assertEqual(link.readlink(), Path(row["endpoint"][7:]))
            self.assertEqual(stat.S_IMODE(link.parent.stat().st_mode), 0o700)
            links.append((link, link.lstat().st_ino, link.parent.stat().st_mtime_ns))
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(row["endpoint"][7:])
                listener.listen(1)
                with socket.socket(socket.AF_UNIX) as client:
                    client.connect(str(link))
                    connection, _ = listener.accept()
                    with connection:
                        client.sendall(b"synthetic")
                        self.assertEqual(connection.recv(9), b"synthetic")
        result = self.run_host("install-discovery")
        self.assertEqual((result.returncode, result.stdout), (0, b""), result.stderr)
        for link, inode, modified in links:
            self.assertEqual((link.lstat().st_ino, link.parent.stat().st_mtime_ns), (inode, modified))
        for account, original in accounts.items():
            current = account.stat()
            self.assertEqual((current.st_uid, current.st_gid, current.st_mode),
                             (original.st_uid, original.st_gid, original.st_mode))

    def test_discovery_checks_every_profile_before_creating_any_path(self):
        row = self.config["profiles"]["work2"]
        parent = Path(row["account_home"]) / "app-server-control"
        parent.mkdir(mode=0o700)
        conflict = parent / "app-server-control.sock"
        for kind in ("file", "foreign-link", "socket"):
            with self.subTest(kind=kind), socket.socket(socket.AF_UNIX) as listener:
                if kind == "file":
                    conflict.write_text("synthetic")
                elif kind == "foreign-link":
                    conflict.symlink_to(self.root / "absent.sock")
                else:
                    listener.bind(str(conflict))
                try:
                    identity = conflict.lstat().st_ino
                    for mode in ("check-discovery", "install-discovery"):
                        result = self.run_host(mode)
                        self.assertEqual(result.returncode, 2, result.stderr)
                        self.assertTrue(result.stderr.startswith(b"ACTION "), result.stderr)
                        self.assertNotIn(str(self.root).encode(), result.stderr)
                        self.assertEqual(conflict.lstat().st_ino, identity)
                        for key in ("personal", "work"):
                            self.assertFalse((Path(self.config["profiles"][key]["account_home"]) /
                                              "app-server-control").exists())
                finally:
                    conflict.unlink()

    def test_discovery_install_requires_existing_owned_accounts_and_private_parents(self):
        missing = Path(self.config["profiles"]["work2"]["account_home"])
        missing.rmdir()
        result = self.run_host("check-discovery")
        self.assertEqual((result.returncode, result.stdout), (0, b""), result.stderr)
        self.assertEqual(self.run_host("install-discovery").returncode, 2)
        missing.mkdir(mode=0o700)
        parent = missing / "app-server-control"
        parent.mkdir(mode=0o755)
        parent.chmod(0o755)
        self.assertEqual(self.run_host("check-discovery").returncode, 2)
        self.assertEqual(self.run_host("install-discovery").returncode, 2)
        self.assertEqual(stat.S_IMODE(parent.stat().st_mode), 0o755)
        parent.rmdir()
        parent.symlink_to(self.root, target_is_directory=True)
        self.assertEqual(self.run_host("install-discovery").returncode, 2)
        parent.unlink()
        self.config["development_user"] = next(account.pw_name for account in pwd.getpwall()
                                                if account.pw_uid != os.getuid())
        self.write_config()
        self.assertEqual(self.run_host("check-discovery").returncode, 2)
        for row in self.config["profiles"].values():
            self.assertFalse((Path(row["account_home"]) / "app-server-control").exists())

    def test_devbox_path_selects_logical_launcher_even_with_inherited_duplicates(self):
        logical = self.root / "bin"
        raw = self.root / ".local/bin"
        logical.mkdir()
        raw.mkdir(parents=True)
        for directory in (logical, raw):
            target = directory / "codex"
            target.write_text("#!/bin/sh\nexit 0\n")
            target.chmod(0o755)
        result = subprocess.run(
            ["zsh", "-f", "-c", 'source "$1"; command -v codex; source "$1"; print -r -- "$PATH"',
             "fixture", str(REPO / "assets/dotfiles/zshenv")], capture_output=True, timeout=3,
            env={**os.environ, "HOME": str(self.root), "PATH": f"{raw}:{logical}:{raw}:/usr/bin:/bin"})
        self.assertEqual(result.returncode, 0, result.stderr)
        selected, search_path = result.stdout.decode().splitlines()
        self.assertEqual(selected, str(logical / "codex"))
        self.assertEqual(search_path.split(":").count(str(logical)), 1)
        self.assertEqual(search_path.split(":").count(str(raw)), 1)

    def test_decode_enforces_byte_bound_and_rejects_duplicate_or_non_json_fields(self):
        for value in (b" " * (host.LIMIT + 1), b'{"profile":"work","profile":"personal"}', b'{"cwd":NaN}'):
            with self.assertRaises(ValueError):
                host.decode(value)




    def test_closed_config_rejects_duplicate_fields_and_non_unix_endpoints(self):
        self.assertEqual(host.load_config(str(self.config_path))["schema_version"], 3)
        self.config_path.write_text('{"schema_version":1,"schema_version":1}')
        with self.assertRaises(ValueError):
            host.load_config(str(self.config_path))

    def test_source_declaration_modes_accept_group_umask_without_changing_input(self):
        source = self.root / "source.json"
        previous = os.umask(0o002)
        try:
            source.write_text(json.dumps(self.config))
        finally:
            os.umask(previous)
        self.assertEqual(stat.S_IMODE(source.stat().st_mode), 0o664)
        before = source.read_bytes()
        for mode in ("validate", "launcher"):
            with self.subTest(mode=mode):
                result = self.run_host("--config", str(source), mode)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(source.read_bytes(), before)
                self.assertEqual(stat.S_IMODE(source.stat().st_mode), 0o664)

    def test_runtime_modes_reject_group_writable_config_before_effects(self):
        self.config_path.chmod(0o664)
        path = Path(self.config["profiles"]["personal"]["endpoint"][7:])
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(path))
            path.chmod(0o600)
            for arguments in (("server", "personal"), ("grant-socket", "personal"),
                              ("check-discovery",), ("install-discovery",)):
                with self.subTest(mode=arguments[0]):
                    self.assertEqual(self.run_host(*arguments).returncode, 1)
                    self.assertFalse((self.root / "codex.calls").exists())
                    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                    self.assertFalse((path.parent / "app-server-control").exists())

    def test_installed_config_remains_protected_in_declaration_modes(self):
        for permissions, uid in ((0o664, 0), (0o644, 1001)):
            metadata = list(self.config_path.stat())
            metadata[0] = stat.S_IFREG | permissions
            metadata[4] = uid
            with patch.object(host, "CONFIG", str(self.config_path)), \
                    patch.object(host.os, "fstat", return_value=os.stat_result(metadata)):
                for mode in ("validate", "launcher"):
                    with self.subTest(mode=mode, permissions=permissions, uid=uid), \
                            patch.object(sys, "argv", [str(HOST), mode]):
                        with self.assertRaises(ValueError):
                            host.main()

    def test_schema_three_has_no_terminal_worker_contract(self):
        self.assertEqual(self.config["schema_version"], 3)
        self.assertNotIn("tmux", self.config)
        self.assertNotIn("launcher_socket", self.config)
        for row in self.config["profiles"].values():
            self.assertNotIn("work_roots", row)
        result = self.run_host("validate")
        self.assertEqual(result.returncode, 0, "shared provider configuration still requires retired worker-launch fields")
        self.assertNotEqual(self.run_host("terminal").returncode, 0)
        self.config["profiles"]["personal"]["endpoint"] = "ws://127.0.0.1:1234"
        self.write_config()
        with self.assertRaises(ValueError):
            host.load_config(str(self.config_path))

    def test_post_bind_grants_only_exact_owned_socket_and_parent(self):
        path = Path(self.config["profiles"]["personal"]["endpoint"][7:])
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(path))
            path.chmod(0o600)
            host.grant_socket(self.config, "personal")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o660)
            self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o750)
        other = Path(self.config["profiles"]["work"]["endpoint"][7:])
        other.write_text("not a socket")
        with self.assertRaises(ValueError):
            host.grant_socket(self.config, "work")
        self.assertEqual(other.read_text(), "not a socket")



if __name__ == "__main__":
    unittest.main()
