#!/usr/bin/env python3
"""Closed host boundary. Codex owns threads; this helper stores no lifecycle state."""

import argparse
import grp
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import stat
import sys
import time

CONFIG = "/etc/codex-shared/profiles.json"
LIMIT = 65536
PROFILES = {"personal", "work", "work2"}
COMMANDS = {"codex": "personal", "codex-work": "work", "codex-work2": "work2"}


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


def load_config(path, *, declaration=False):
    with open(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if (not stat.S_ISREG(metadata.st_mode)
                or ((not declaration or path == CONFIG) and metadata.st_mode & 0o022)
                or (path == CONFIG and metadata.st_uid != 0)):
            invalid()
        config = decode(stream.read(LIMIT + 1))
    fields(config, {"schema_version", "development_user",
                    "jarvis_user", "client_group", "binary",
                    "cognition_cwd_parent", "profiles"})
    if type(config["schema_version"]) is not int or config["schema_version"] != 3:
        invalid()
    for key in ("development_user", "jarvis_user", "client_group"):
        if not isinstance(config[key], str) or not re.fullmatch(r"[a-z_][a-z0-9_-]*", config[key]):
            invalid()
    for key in ("binary", "cognition_cwd_parent"):
        absolute(config[key])
    fields(config["profiles"], PROFILES)
    endpoints, homes = set(), set()
    for row in config["profiles"].values():
        fields(row, {"account_home", "endpoint"})
        homes.add(absolute(row["account_home"]))
        if not isinstance(row["endpoint"], str) or not row["endpoint"].startswith("unix:///"):
            invalid()
        endpoints.add(absolute(row["endpoint"][7:]))
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
                                         "server", "grant-socket",
                                         "check-discovery", "install-discovery"))
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    # Pure declaration transforms consume source checkouts; runtime inputs stay protected.
    config = load_config(args.config, declaration=args.mode in ("validate", "launcher"))
    if args.host != "devbox" and args.mode == "grant-socket":
        invalid()
    if args.mode == "validate":
        if args.arguments:
            invalid()
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
    except (ValueError, OSError, KeyError, TimeoutError):
        print("ERROR  shared Codex boundary: invalid input or unavailable dependency", file=sys.stderr)
        sys.exit(1)
