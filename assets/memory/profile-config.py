#!/usr/bin/env python3
"""Use native configuration writers on private copies of the owned profile key."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

from jarvis.collector import CollectorConfig


def main() -> None:
    bundle, collector_path, owner_home, output = (Path(value) for value in sys.argv[1:])
    profiles = json.loads(bundle.read_bytes())
    collector = CollectorConfig.load(collector_path)
    if (
        not isinstance(profiles, list)
        or len(profiles) != len(collector.homes)
        or {profile["account"] for profile in profiles} != set(collector.homes)
    ):
        raise ValueError("profile mapping differs from the native homes")
    for profile in profiles:
        account = profile["account"]
        home = collector.homes[account]
        root = owner_home / (
            f".{home.provider}" if account.endswith("-personal") else f".{account}"
        )
        if (
            profile.keys()
            != {"account", "provider", "state_root", "connect", "bearer_env", "url"}
            or profile["provider"] != home.provider
            or Path(profile["state_root"]) != root
            or home.state_root != root
            or type(profile["connect"]) is not bool
            or profile["bearer_env"]
            != "JARVIS_MEMORY_" + account.upper().replace("-", "_") + "_BEARER"
            or profile["url"] != collector.service_url + "/v1/mcp"
        ):
            raise ValueError("invalid owned native profile mapping")
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    for profile in profiles:
        root = Path(profile["state_root"])
        provider = profile["provider"]
        account = profile["account"]
        if provider == "codex":
            target = root / "config.toml"
            value = tomllib.loads(target.read_text()) if target.exists() else {}
            current = value.get("mcp_servers", {}).get("jarvis-memory")
            desired = {
                "url": profile["url"],
                "bearer_token_env_var": profile["bearer_env"],
            }
        else:
            target = (
                owner_home / ".claude.json"
                if account == "claude-personal"
                else root / ".claude.json"
            )
            value = json.loads(target.read_bytes()) if target.exists() else {}
            current = value.get("mcpServers", {}).get("jarvis-memory")
            desired = {
                "type": "http",
                "url": profile["url"],
                "headers": {"Authorization": "Bearer ${" + profile["bearer_env"] + "}"},
            }
        if current == (desired if profile["connect"] else None):
            continue
        if provider == "claude":
            servers = value.setdefault("mcpServers", {})
            if profile["connect"]:
                servers["jarvis-memory"] = desired
            else:
                servers.pop("jarvis-memory", None)
            candidate = output / account
            candidate.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
            os.chmod(candidate, 0o600)
            print(str(candidate) + "\t" + str(target))
            continue
        with tempfile.TemporaryDirectory(
            prefix=".native-config-", dir=output
        ) as temporary:
            stage = Path(temporary)
            name = "config.toml"
            if target.exists():
                shutil.copyfile(target, stage / name)
            environment = dict(os.environ)
            environment.pop("CODEX_HOME", None)
            environment.pop("CLAUDE_CONFIG_DIR", None)
            environment["CODEX_HOME"] = str(stage)
            command = [str(owner_home / ".local/bin/codex"), "mcp"]
            if profile["connect"]:
                command += [
                    "add",
                    "jarvis-memory",
                    "--url",
                    profile["url"],
                    "--bearer-token-env-var",
                    profile["bearer_env"],
                ]
            else:
                command += ["remove", "jarvis-memory"]
            subprocess.run(
                command,
                env=environment,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            result = stage / name
            updated = tomllib.loads(result.read_text())
            actual = updated.get("mcp_servers", {}).get("jarvis-memory")
            if actual != (desired if profile["connect"] else None):
                raise ValueError("native writer did not install the declared server")
            for document in (value, updated):
                servers = document.get("mcp_servers", {})
                servers.pop("jarvis-memory", None)
                if not servers:
                    document.pop("mcp_servers", None)
            if value != updated:
                raise ValueError("native writer changed unrelated configuration")
            candidate = output / account
            shutil.copyfile(result, candidate)
            os.chmod(candidate, 0o600)
        print(str(candidate) + "\t" + str(target))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        raise SystemExit(
            "could not render native memory configuration; private inputs are omitted"
        ) from None
