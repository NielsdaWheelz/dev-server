"""Host boundary fixtures, not Linux/systemd/tmux/provider qualification."""

import base64
import grp
import hashlib
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

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[1]
HOST = REPO / "assets/codex/codex-shared.py"
spec = importlib.util.spec_from_file_location("codex_host", HOST)
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
HANDLE = "01987654-1234-7000-8000-123456789abc"

FAKE = '''#!/usr/bin/env python3
import json, os, pathlib, sys
path = pathlib.Path(__file__)
args = sys.argv[1:]
if path.name == "codex" and args == ["--version"]:
    print("codex-cli 0.153.4")
    raise SystemExit(0)
with path.with_suffix(".calls").open("a") as stream:
    stream.write(json.dumps({"argv": args, "env": dict(os.environ), "cwd": os.getcwd()}) + "\\n")
if path.name == "tmux":
    mode_path = path.with_suffix(".mode")
    mode = mode_path.read_text() if mode_path.exists() else "ok"
    if args[0] == "new-session":
        if mode == "create-failed": raise SystemExit(1)
        path.with_suffix(".name").write_text(args[args.index("-s") + 1])
        print("$17")
    elif args[0] == "display-message":
        name = path.with_suffix(".name").read_text()
        print("$18\\twrong" if mode == "observe-failed" else "$17\\t" + name)
    else:
        raise SystemExit(65)
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
                           binary=str(self.root / "codex"), tmux=str(self.root / "tmux"),
                           cognition_cwd_parent=str(self.root / "empty"),
                           launcher_socket=str(self.root / "launch.sock"))
        Path(self.config["cognition_cwd_parent"]).mkdir()
        for key, row in self.config["profiles"].items():
            directory = self.root / Path(row["account_home"]).name
            directory.mkdir(mode=0o700)
            row.update(account_home=str(directory), endpoint=f"unix://{directory}/server.sock",
                       work_roots=[str(self.work)])
        for command in ("codex", "tmux"):
            target = self.root / command
            target.write_text(FAKE)
            target.chmod(0o755)
        self.config_path = self.root / "profiles.json"
        self.write_config()

    def write_config(self):
        self.config_path.write_text(json.dumps(self.config))
        self.config_path.chmod(0o600)

    def request(self, **updates):
        value = {"kind": "LaunchTerminal", "profile": "personal", "thread_handle": HANDLE,
                 "cwd": str(self.work), "tmux_name": "review-13"}
        value.update(updates)
        return value

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

    def test_workstation_servers_and_clients_share_profiles_without_restricting_manual_cwd(self):
        self.prepare_workstation()
        for machine in ("macbook", "arch"):
            for command, key in host.COMMANDS.items():
                with self.subTest(host=machine, profile=key):
                    endpoint = f"unix://{self.root}/.local/run/codex-shared/{key}/app-server.sock"
                    result = self.run_host("--host", machine, "tui", command, "resume", HANDLE, cwd=self.root)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    call = self.calls(".local/bin/codex")[-1]
                    self.assertEqual(call["argv"], ["--remote", endpoint, "--sandbox", "workspace-write",
                                                   "--ask-for-approval", "on-request", "resume", HANDLE])
                    self.assertEqual(call["cwd"], str(self.root))
                    self.assertEqual(call["env"]["HOME"], str(self.root))
                    self.assertEqual(call["env"]["CODEX_HOME"], self.config["profiles"][key]["account_home"])
                    self.assertEqual(call["env"]["TERM"], "xterm-256color")
                    self.assertEqual(call["env"]["COLORTERM"], "truecolor")
                    self.assertIn(str(self.root / ".local/share/mise/shims"), call["env"]["PATH"].split(":"))
                    if machine == "macbook":
                        self.assertIn("/opt/homebrew/bin", call["env"]["PATH"].split(":"))
                    result = self.run_host("--host", machine, "server", key)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    call = self.calls(".local/bin/codex")[-1]
                    self.assertEqual(call["argv"][-3:], ["app-server", "--listen", endpoint])
                    self.assertEqual(call["cwd"], str(self.root / ".local/share/codex-shared/empty"))
                    self.assertEqual(call["env"]["TERM"], "dumb")
                    self.assertNotIn("COLORTERM", call["env"])
            for call in self.calls(".local/bin/codex"):
                for key in ("TMUX", "TMUX_PANE", "TMUX_TMPDIR", "OPENAI_API_KEY", "JARVIS_SECRET_FIXTURE"):
                    self.assertNotIn(key, call["env"])

    def test_workstation_rejects_privileged_modes_and_open_provider_arguments_before_effects(self):
        self.prepare_workstation()
        for machine in ("macbook", "arch"):
            for arguments in (("terminal",), ("grant-socket", "personal"),
                              ("tui", "codex", "exec"), ("tui", "codex", "resume", "last")):
                with self.subTest(host=machine, arguments=arguments):
                    self.assertNotEqual(self.run_host("--host", machine, *arguments).returncode, 0)
        self.assertEqual(self.calls(".local/bin/codex"), [])
        self.assertEqual(self.calls("tmux"), [])

    def test_fresh_manual_thread_explicitly_uses_the_callers_working_directory(self):
        self.prepare_workstation()
        for machine in ("devbox", "macbook", "arch"):
            with self.subTest(host=machine):
                result = self.run_host("--host", machine, "tui", "codex")
                self.assertEqual(result.returncode, 0, result.stderr)
                binary = "codex" if machine == "devbox" else ".local/bin/codex"
                self.assertEqual(self.calls(binary)[-1]["argv"][-2:], ["--cd", str(self.work)])

    def test_workstation_launcher_runs_installed_helper_with_exact_host_and_basename(self):
        self.prepare_workstation()
        installed = self.root / ".local/libexec/codex-shared"
        installed.parent.mkdir(parents=True)
        installed.write_bytes(HOST.read_bytes())
        configuration = self.root / ".config/codex-shared/profiles.json"
        configuration.parent.mkdir(parents=True)
        configuration.write_text(json.dumps(self.config))
        commands = self.root / "bin"
        commands.mkdir()
        for machine, interpreter in (("macbook", "/opt/homebrew/bin/python3"), ("arch", "/usr/bin/python3")):
            result = self.run_host("--host", machine, "launcher")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"exec {interpreter} ".encode(), result.stdout)
            self.assertIn(f"--host {machine} tui ".encode(), result.stdout)
            for command, profile in host.COMMANDS.items():
                launcher = commands / command
                launcher.write_bytes(result.stdout)
                # Interpreter selection is asserted above; execution uses this
                # test host's Python to exercise both real generated wrappers.
                launcher.write_text(launcher.read_text().replace(interpreter, sys.executable))
                child = subprocess.run(["bash", str(launcher), "resume", HANDLE], cwd=self.root,
                                       env={**os.environ, "HOME": str(self.root)},
                                       capture_output=True, timeout=15)
                self.assertEqual(child.returncode, 0, child.stderr)
                call = self.calls(".local/bin/codex")[-1]
                self.assertEqual(call["argv"][1], f"unix://{self.root}/.local/run/codex-shared/{profile}/app-server.sock")
                self.assertEqual(call["argv"][-2:], ["resume", HANDLE])

    def test_manual_and_backend_select_exact_profile_and_clean_environment(self):
        for command, key in host.COMMANDS.items():
            result = self.run_host("tui", command, "resume", HANDLE)
            self.assertEqual(result.returncode, 0, result.stderr)
            call = self.calls("codex")[-1]
            row = self.config["profiles"][key]
            self.assertEqual(call["argv"], ["--remote", row["endpoint"], "--sandbox", "workspace-write",
                                            "--ask-for-approval", "on-request", "resume", HANDLE])
            self.assertEqual(call["env"]["CODEX_HOME"], row["account_home"])
            self.assertNotIn("TMUX", call["env"])
            self.assertNotIn("JARVIS_SECRET_FIXTURE", call["env"])
            result = self.run_host("server", key)
            self.assertEqual(result.returncode, 0, result.stderr)
            call = self.calls("codex")[-1]
            self.assertEqual(call["argv"][-3:], ["app-server", "--listen", row["endpoint"]])
            self.assertEqual(call["cwd"], self.config["cognition_cwd_parent"])

    def test_manual_rejects_non_closed_options_without_invoking_provider(self):
        for args in (("exec",), ("--remote", "unix:///wrong"), ("resume", "short"),
                     ("resume", HANDLE, "prompt"), ("--config", "elsewhere"),
                     ("--yolo", "--yolo"),
                     ("--yolo", "--dangerously-bypass-approvals-and-sandbox"),
                     ("--yolo", "--sandbox", "workspace-write"),
                     ("--yolo", "--ask-for-approval", "never"),
                     ("resume", HANDLE, "--yolo", "extra")):
            with self.subTest(args=args):
                result = self.run_host("tui", "codex", *args)
                self.assertEqual(result.returncode, 64)
                self.assertIn(b"Usage: {codex|codex-work|codex-work2}", result.stderr)
                self.assertIn(b"[resume UUID]", result.stderr)
                self.assertNotIn(HANDLE.encode(), result.stderr)
                self.assertNotIn(b"elsewhere", result.stderr)
        self.assertEqual(self.calls("codex"), [])

    def test_manual_yolo_selects_native_bypass_without_conflicting_defaults(self):
        for flag in ("--yolo", "--dangerously-bypass-approvals-and-sandbox"):
            for command in host.COMMANDS:
                for rest in ((flag,), (flag, "resume", HANDLE), ("resume", flag, HANDLE),
                             ("resume", HANDLE, flag)):
                    with self.subTest(command=command, arguments=rest):
                        result = self.run_host("tui", command, *rest)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        suffix = ["resume", HANDLE] if "resume" in rest else ["--cd", str(self.work)]
                        row = self.config["profiles"][host.COMMANDS[command]]
                        self.assertEqual(self.calls("codex")[-1]["argv"],
                                         ["--remote", row["endpoint"], "--yolo", *suffix])

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

    def test_declared_root_cannot_redirect_through_a_symlink(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        self.config["profiles"]["personal"]["work_roots"] = [str(alias)]
        self.assertEqual(host.handle_request(self.config, self.request())["kind"], "Rejected")
        self.assertEqual(self.calls("tmux"), [])

    def test_launch_observes_exact_terminal_and_passes_argv_without_a_shell(self):
        result = host.handle_request(self.config, self.request())
        self.assertEqual(result, {"kind": "Started", "terminal": {"tmux_session_id": "$17", "tmux_name": "review-13"}})
        create, observe = self.calls("tmux")
        argv = create["argv"]
        self.assertEqual(argv[:9], ["new-session", "-d", "-P", "-F", "#{session_id}",
                                   "-s", "review-13", "-c", str(self.work)])
        self.assertEqual(argv[9:11], ["/usr/bin/env", "-i"])
        self.assertEqual(argv[-9:], [self.config["binary"], "--remote",
                                    self.config["profiles"]["personal"]["endpoint"],
                                    "--sandbox", "workspace-write", "--ask-for-approval", "on-request",
                                    "resume", HANDLE])
        self.assertNotIn("-L", argv)
        self.assertNotIn("-S", argv)
        self.assertNotIn("TMUX", create["env"])
        self.assertEqual(observe["argv"], ["display-message", "-p", "-t", "$17", "#{session_id}\t#{session_name}"])

    def test_resolve_cwd_returns_permitted_canonical_path_without_launching(self):
        alias = self.work / "alias"
        target = self.work / "repository"
        target.mkdir()
        alias.symlink_to(target, target_is_directory=True)
        request = {"kind": "ResolveCwd", "profile": "work", "cwd": str(alias)}
        self.assertEqual(host.handle_request(self.config, request), {"kind": "Resolved", "cwd": str(target)})
        self.assertEqual(self.calls("tmux"), [])
        self.assertEqual(self.calls("codex"), [])
        target.rmdir()
        target.symlink_to(self.root, target_is_directory=True)
        result = host.handle_request(self.config, self.request(cwd=str(target)))
        self.assertEqual(result["kind"], "Rejected")
        self.assertEqual(self.calls("tmux"), [])

    def test_invalid_requests_have_no_terminal_effect(self):
        escape = self.work / "escape"
        escape.symlink_to(self.root, target_is_directory=True)
        untagged = self.request()
        del untagged["kind"]
        invalid = [untagged, self.request(kind="ResolveCwd"), self.request(kind="unknown"),
                   self.request(prompt="forbidden"), self.request(yolo=True), self.request(profile="other"),
                   self.request(thread_handle="last"), self.request(cwd=str(self.root)),
                   self.request(cwd=str(escape)), self.request(tmux_name="bad:name"),
                   self.request(tmux_name="a" * 65), self.request(cwd="/" + "a" * 4096)]
        for request in invalid:
            with self.subTest(request=request.keys()):
                self.assertEqual(host.handle_request(self.config, request)["kind"], "Rejected")
        self.assertEqual(self.calls("tmux"), [])

    def test_ambiguous_create_and_observation_are_not_replayed_or_cleaned_up(self):
        for mode, stage in (("create-failed", "create"), ("observe-failed", "observe")):
            (self.root / "tmux.mode").write_text(mode)
            before = len(self.calls("tmux"))
            result = host.handle_request(self.config, self.request())
            self.assertEqual(result, {"kind": "Unknown", "stage": stage})
            calls = self.calls("tmux")[before:]
            self.assertEqual([call["argv"][0] for call in calls],
                             ["new-session"] if stage == "create" else ["new-session", "display-message"])

    def test_closed_config_rejects_duplicate_fields_and_non_unix_endpoints(self):
        self.assertEqual(host.load_config(str(self.config_path))["version"], "0.153.4")
        self.config_path.write_text('{"schema_version":1,"schema_version":1}')
        with self.assertRaises(ValueError):
            host.load_config(str(self.config_path))
        self.config["profiles"]["personal"]["endpoint"] = "ws://127.0.0.1:1234"
        self.write_config()
        with self.assertRaises(ValueError):
            host.load_config(str(self.config_path))

    def test_package_is_verified_from_downloaded_bytes_not_npm_claim(self):
        package = self.root / "package.tgz"
        data = b"synthetic package fixture"
        package.write_bytes(data)
        (self.root / "metadata.json").write_text(json.dumps([{"filename": package.name}]))
        self.config["package"]["integrity"] = "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode()
        self.config["package"]["shasum"] = hashlib.sha1(data).hexdigest()
        self.write_config()
        result = self.run_host("verify-package", str(self.root))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.decode().strip(), str(package))
        package.write_bytes(data + b"tampered")
        self.assertNotEqual(self.run_host("verify-package", str(self.root)).returncode, 0)

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

    @unittest.skipUnless(hasattr(socket, "SO_PEERCRED"), "NOT_RUN: Linux peer-credential boundary")
    def test_socket_request_uses_real_peer_credentials(self):
        client, server = socket.socketpair()
        with client, server:
            with subprocess.Popen([sys.executable, str(HOST), "--config", str(self.config_path), "terminal"],
                                  stdin=server, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE) as child:
                client.settimeout(3)
                client.sendall(json.dumps(self.request()).encode() + b"\n")
                response = client.makefile("rb").readline(host.LIMIT + 1)
                self.assertEqual(json.loads(response)["kind"], "Started")
                child.communicate(timeout=3)
                self.assertEqual(child.returncode, 0)

    @unittest.skipUnless(hasattr(socket, "SO_PEERCRED"), "NOT_RUN: Linux peer-credential boundary")
    def test_unauthorized_peer_is_rejected_before_reading_request(self):
        self.config["jarvis_user"] = next(account.pw_name for account in pwd.getpwall() if account.pw_uid != os.getuid())
        self.write_config()
        client, server = socket.socketpair()
        with client, server:
            with subprocess.Popen([sys.executable, str(HOST), "--config", str(self.config_path), "terminal"],
                                  stdin=server, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE) as child:
                client.settimeout(3)
                response = client.makefile("rb").readline(host.LIMIT + 1)
                self.assertEqual(json.loads(response), {"kind": "Rejected", "stage": "validate", "reason": "unauthorized"})
                child.communicate(timeout=3)
                self.assertEqual(child.returncode, 0)
        self.assertEqual(self.calls("tmux"), [])


if __name__ == "__main__":
    unittest.main()
