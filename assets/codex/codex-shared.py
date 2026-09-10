#!/usr/bin/env python3
"""Closed host boundary. Codex owns threads; this helper stores no lifecycle state."""

import argparse
import grp
import json
import os
from pathlib import Path
import pwd
import re
import selectors
import shlex
import socket
import stat
import struct
import subprocess
import sys
import time

CONFIG = "/etc/codex-shared/profiles.json"
LIMIT = 65536
PROFILES = {"personal", "work", "work2"}
COMMANDS = {"codex": "personal", "codex-work": "work", "codex-work2": "work2"}
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}\Z")
THREAD = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\Z")


def strict_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate field")
        value[key] = item
    return value


def decode(data):
    if len(data) > LIMIT:
        raise ValueError("oversized input")
    return json.loads(data.decode("utf-8"), object_pairs_hook=strict_object,
                      parse_constant=lambda _: invalid())


def invalid():
    raise ValueError("invalid declaration")


def fields(value, expected):
    if not isinstance(value, dict) or value.keys() != set(expected):
        invalid()


def absolute(value, canonical=True):
    if (not isinstance(value, str) or not value.startswith("/") or value.startswith("//")
            or len(value.encode("utf-8")) > 4096
            or any(ord(character) < 32 or ord(character) == 127 for character in value)
            or (canonical and os.path.normpath(value) != value) or value == "/"):
        invalid()
    return value


def load_config(path):
    with open(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_mode & 0o022
                or (path == CONFIG and metadata.st_uid != 0)):
            invalid()
        config = decode(stream.read(LIMIT + 1))
    fields(config, {"schema_version", "development_user",
                    "jarvis_user", "client_group", "binary", "tmux",
                    "cognition_cwd_parent", "launcher_socket", "profiles"})
    if type(config["schema_version"]) is not int or config["schema_version"] != 2:
        invalid()
    for key in ("development_user", "jarvis_user", "client_group"):
        if not isinstance(config[key], str) or not re.fullmatch(r"[a-z_][a-z0-9_-]*", config[key]):
            invalid()
    for key in ("binary", "tmux", "cognition_cwd_parent", "launcher_socket"):
        absolute(config[key])
    fields(config["profiles"], PROFILES)
    endpoints, homes = set(), set()
    for row in config["profiles"].values():
        fields(row, {"account_home", "endpoint", "work_roots"})
        homes.add(absolute(row["account_home"]))
        if not isinstance(row["endpoint"], str) or not row["endpoint"].startswith("unix:///"):
            invalid()
        endpoints.add(absolute(row["endpoint"][7:]))
        if not isinstance(row["work_roots"], list) or not row["work_roots"]:
            invalid()
        for root in row["work_roots"]:
            absolute(root)
    if len(endpoints) != 3 or len(homes) != 3:
        invalid()
    return config


def profile(config, key):
    if not isinstance(key, str) or key not in PROFILES:
        invalid()
    return config["profiles"][key]


def environment(config, row):
    account = pwd.getpwnam(config["development_user"])
    home = config.get("home", account.pw_dir)
    path = f"{home}/bin:{home}/.local/bin:{home}/.local/share/mise/shims:"
    if config.get("host") == "macbook":
        path += "/opt/homebrew/bin:"
    return {"HOME": home, "USER": account.pw_name, "LOGNAME": account.pw_name,
            "CODEX_HOME": row["account_home"], "LANG": "C.UTF-8",
            "PATH": path + "/usr/local/bin:/usr/bin:/bin", "TERM": "dumb"}


def permitted_cwd(row, value, resolve=False):
    absolute(value, canonical=not resolve)
    actual = Path(value).resolve(strict=True)
    if (not resolve and str(actual) != value) or not actual.is_dir():
        invalid()
    roots = []
    for root in row["work_roots"]:
        canonical = Path(root).resolve(strict=True)
        if str(canonical) != root or not canonical.is_dir():
            invalid()
        roots.append(canonical)
    if not any(actual.is_relative_to(root) for root in roots):
        invalid()
    return str(actual)


def bounded_command(argv, env, timeout=10):
    """Bound process I/O; timeout stops only our client, never a backend or tmux."""
    with subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, env=env, close_fds=True) as child:
        try:
            result = bytearray()
            deadline = time.monotonic() + timeout
            with selectors.DefaultSelector() as selector:
                selector.register(child.stdout, selectors.EVENT_READ)
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        raise TimeoutError
                    chunk = os.read(child.stdout.fileno(), min(4096, LIMIT + 1 - len(result)))
                    if not chunk:
                        break
                    result.extend(chunk)
                    if len(result) > LIMIT:
                        raise ValueError("oversized command response")
            return child.wait(timeout=max(0.01, deadline - time.monotonic())), bytes(result)
        except BaseException:
            child.kill()
            child.wait()
            raise


def handle_request(config, request):
    try:
        if isinstance(request, dict) and request.get("kind") == "ResolveCwd":
            fields(request, {"kind", "profile", "cwd"})
            row = profile(config, request["profile"])
            return {"kind": "Resolved", "cwd": permitted_cwd(row, request["cwd"], resolve=True)}
        fields(request, {"kind", "profile", "thread_handle", "cwd", "tmux_name"})
        if request["kind"] != "LaunchTerminal":
            invalid()
        row = profile(config, request["profile"])
        name = request["tmux_name"]
        if not isinstance(name, str) or not NAME.fullmatch(name):
            invalid()
        cwd = permitted_cwd(row, request["cwd"])
        handle = request["thread_handle"]
        if not isinstance(handle, str) or not THREAD.fullmatch(handle):
            invalid()
        argv = [config["binary"], "--remote", row["endpoint"], "--sandbox", "workspace-write",
                "--ask-for-approval", "on-request", "resume", handle]
        env = environment(config, row)
        env["TERM"] = "tmux-256color"
    except (ValueError, OSError, KeyError, TimeoutError, subprocess.TimeoutExpired):
        return {"kind": "Rejected", "stage": "validate", "reason": "invalid_request"}
    # A pre-existing default tmux server has its own environment. env -i clears
    # that environment in the pane too; clearing only the client is insufficient.
    command = [config["tmux"], "new-session", "-d", "-P", "-F", "#{session_id}",
               "-s", name, "-c", cwd, "/usr/bin/env", "-i"]
    command += [f"{key}={value}" for key, value in env.items()] + argv
    try:
        status, output = bounded_command(command, env)
        if status != 0 or not re.fullmatch(rb"\$[0-9]+\n", output):
            raise ValueError("unconfirmed create")
        session_id = output.decode("ascii").strip()
    except (ValueError, OSError, TimeoutError, subprocess.TimeoutExpired):
        return {"kind": "Unknown", "stage": "create"}
    try:
        status, output = bounded_command(
            [config["tmux"], "display-message", "-p", "-t", session_id,
             "#{session_id}\t#{session_name}"], env)
        if status != 0 or output != f"{session_id}\t{name}\n".encode():
            raise ValueError("unconfirmed terminal")
    except (ValueError, OSError, TimeoutError, subprocess.TimeoutExpired):
        return {"kind": "Unknown", "stage": "observe"}
    return {"kind": "Started", "terminal": {"tmux_session_id": session_id, "tmux_name": name}}


def serve_request(config, connection):
    connection.settimeout(10)
    try:
        # Production is Linux. Authenticate before consuming even one byte.
        _, uid, _ = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
        if uid != pwd.getpwnam(config["jarvis_user"]).pw_uid:
            result = {"kind": "Rejected", "stage": "validate", "reason": "unauthorized"}
        else:
            with connection.makefile("rb") as stream:
                data = stream.readline(LIMIT + 1)
            if len(data) > LIMIT or not data.endswith(b"\n") or b"\n" in data[:-1]:
                invalid()
            result = handle_request(config, decode(data))
    except (ValueError, OSError, KeyError, AttributeError):
        result = {"kind": "Rejected", "stage": "validate", "reason": "invalid_request"}
    response = json.dumps(result, separators=(",", ":")).encode() + b"\n"
    connection.sendall(response)


def grant_socket(config, key):
    """Native bind ends with 0600. Broaden only after that owned inode exists."""
    path = Path(profile(config, key)["endpoint"][7:])
    uid = pwd.getpwnam(config["development_user"]).pw_uid
    gid = grp.getgrnam(config["client_group"]).gr_gid
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        parent = path.parent.lstat()
        if not stat.S_ISDIR(parent.st_mode) or (parent.st_uid, parent.st_gid) != (uid, gid):
            invalid()
        try:
            item = path.lstat()
        except FileNotFoundError:
            time.sleep(0.05)
            continue
        if not stat.S_ISSOCK(item.st_mode) or (item.st_uid, item.st_gid) != (uid, gid):
            invalid()
        if stat.S_IMODE(item.st_mode) == 0o600:
            os.chmod(path, 0o660, follow_symlinks=False)
            os.chmod(path.parent, 0o750, follow_symlinks=False)
            return
        time.sleep(0.05)
    raise TimeoutError


def discovery_links(config, *, allow_missing_accounts):
    links = []
    try:
        uid = pwd.getpwnam(config["development_user"]).pw_uid
        if not allow_missing_accounts and os.geteuid() != uid:
            invalid()
        for key in ("personal", "work", "work2"):
            row = profile(config, key)
            account = Path(row["account_home"])
            try:
                metadata = account.lstat()
            except FileNotFoundError:
                if allow_missing_accounts:
                    continue
                raise
            if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != uid:
                invalid()
            parent = account / "app-server-control"
            try:
                metadata = parent.lstat()
            except FileNotFoundError:
                pass
            else:
                if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != uid
                        or stat.S_IMODE(metadata.st_mode) != 0o700):
                    invalid()
            link = parent / "app-server-control.sock"
            target = row["endpoint"][7:]
            if link.is_symlink():
                if os.readlink(link) != target:
                    invalid()
            elif link.exists():
                invalid()
            links.append((link, target))
    except (OSError, ValueError, KeyError):
        print("ACTION shared Codex discovery requires owned account directories and conflict-free private paths",
              file=sys.stderr)
        raise SystemExit(2) from None
    return links


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=CONFIG)
    parser.add_argument("--host", choices=("devbox", "macbook", "arch"), default="devbox")
    parser.add_argument("mode", choices=("validate", "launcher",
                                         "server", "grant-socket", "terminal",
                                         "check-discovery", "install-discovery"))
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    config = load_config(args.config)
    if args.host != "devbox" and args.mode in ("terminal", "grant-socket"):
        invalid()
    if args.mode in ("validate", "terminal"):
        if args.arguments:
            invalid()
        if args.mode == "terminal":
            with socket.socket(fileno=os.dup(0)) as connection:
                serve_request(config, connection)
        return
    if args.host != "devbox":
        home = absolute(os.path.expanduser("~"))
        config = {"host": args.host, "home": home,
                  "development_user": pwd.getpwuid(os.getuid()).pw_name,
                  "binary": f"{home}/.local/bin/codex",
                  "cognition_cwd_parent": f"{home}/.local/share/codex-shared/empty",
                  "profiles": {key: {"account_home": f"{home}/{Path(row['account_home']).name}",
                                     "endpoint": f"unix://{home}/.local/run/codex-shared/{key}/app-server.sock"}
                               for key, row in config["profiles"].items()}}
    if args.mode == "launcher" and not args.arguments:
        print('#!/usr/bin/env bash\ncase "${0##*/}" in')
        for command, key in COMMANDS.items():
            print(f'  {command}) export CODEX_HOME={shlex.quote(profile(config, key)["account_home"])} ;;')
        print('  *) exit 64 ;;\nesac')
        print(f'exec {shlex.quote(config["binary"])} "$@"')
        return
    if args.mode in ("check-discovery", "install-discovery") and not args.arguments:
        links = discovery_links(config, allow_missing_accounts=args.mode == "check-discovery")
        if args.mode == "install-discovery":
            changed = False
            for link, target in links:
                if not link.parent.exists():
                    link.parent.mkdir(mode=0o700)
                    link.parent.chmod(0o700)
                    changed = True
                if not link.is_symlink():
                    link.symlink_to(target)
                    changed = True
            if changed:
                print("CHANGED codex.runtime")
        return
    if args.mode in ("server", "grant-socket") and len(args.arguments) == 1:
        key = args.arguments[0]
        row = profile(config, key)
        if args.mode == "grant-socket":
            grant_socket(config, key)
            return
        if args.host != "devbox":
            cwd = Path(config["cognition_cwd_parent"])
            metadata = cwd.lstat()
            if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid()
                    or stat.S_IMODE(metadata.st_mode) != 0o700 or any(cwd.iterdir())):
                invalid()
        os.chdir(config["cognition_cwd_parent"])
        argv = [config["binary"], "app-server", "--listen", row["endpoint"]]
        os.execve(config["binary"], argv, environment(config, row))
    invalid()


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TimeoutError, subprocess.TimeoutExpired):
        print("ERROR  shared Codex boundary: invalid input or unavailable dependency", file=sys.stderr)
        sys.exit(1)
