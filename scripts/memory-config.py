#!/usr/bin/env python3
"""Render the fixed fleet's private memory bundle; Jarvis owns its semantics."""

import argparse
import hashlib
import json
import os
import re
import secrets
import tempfile
from pathlib import Path

from jarvis.collector import CollectorConfig
from jarvis.memory_config import MEMORY_IDENTITIES, MemoryConfig, memory_origin


def install(path: Path, value: str) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    encoded = value.encode()
    if path.exists() and path.read_bytes() == encoded:
        os.chmod(path, 0o600)
        return
    descriptor, candidate = tempfile.mkstemp(prefix=".memory-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
        os.chmod(candidate, 0o600)
        os.replace(candidate, path)
    finally:
        if os.path.exists(candidate):
            os.unlink(candidate)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--declaration", type=Path, required=True)
    parser.add_argument("--credentials", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--home", action="append", required=True)
    parser.add_argument("--rotate", action="append", default=[])
    args = parser.parse_args()
    try:
        origin = memory_origin(args.url)
        homes = dict(value.split("=", 1) for value in args.home)
        if set(homes) != {"macbook", "arch", "devbox"} or any(
            not Path(value).is_absolute() for value in homes.values()
        ):
            raise ValueError("declare all three absolute host homes")
        declaration = json.loads(args.declaration.read_bytes())
        lanes = declaration["lanes"]
        if {(lane["machine"], lane["account"]) for lane in lanes} != MEMORY_IDENTITIES:
            raise ValueError("declare all sixteen lanes")
        credential_keys = (
            {f"capture:{machine}" for machine in homes}
            | {f"client:{machine}:{account}" for machine, account in MEMORY_IDENTITIES}
            | {"client:nexus-owner"}
        )
        credentials = (
            json.loads(args.credentials.read_bytes())
            if args.credentials.exists()
            else {}
        )
        if not isinstance(credentials, dict) or any(
            key not in credential_keys
            or not isinstance(value, str)
            or re.fullmatch(r"jmem_[0-9a-f]{64}", value) is None
            for key, value in credentials.items()
        ):
            raise ValueError("invalid private credentials")
        needed = {f"capture:{machine}" for machine in homes} | {
            f"client:{lane['machine']}:{lane['account']}"
            for lane in lanes
            if lane.get("connect") is True
        }
        nexus = declaration.get("nexus_client")
        if nexus is not None and not isinstance(nexus, dict):
            raise ValueError("invalid nexus client declaration")
        if nexus is not None and nexus.get("connect") is True:
            needed.add("client:nexus-owner")
        if not set(args.rotate).issubset(needed):
            raise ValueError("rotation must name a current capture/connected client")
        for key in needed:
            if key not in credentials or key in args.rotate:
                credentials[key] = "jmem_" + secrets.token_hex(32)
        declaration["capture_bearer_sha256"] = {
            machine: hashlib.sha256(
                credentials[f"capture:{machine}"].encode()
            ).hexdigest()
            for machine in homes
        }
        for lane in lanes:
            lane["client_bearer_sha256"] = (
                hashlib.sha256(
                    credentials[f"client:{lane['machine']}:{lane['account']}"].encode()
                ).hexdigest()
                if lane.get("connect") is True
                else None
            )
        if nexus is not None:
            nexus["bearer_sha256"] = (
                hashlib.sha256(credentials["client:nexus-owner"].encode()).hexdigest()
                if nexus.get("connect") is True
                else None
            )
        config = MemoryConfig.model_validate_json(json.dumps(declaration))
        if origin not in config.origins:
            raise ValueError("service URL must appear in declared origins")
        rendered: dict[Path, str] = {
            args.output / "server.json": config.model_dump_json(indent=2) + "\n"
        }
        nexus = config.nexus_client
        nexus_config = (
            {
                "kind": "Present",
                "value": {
                    "client": nexus.client,
                    "owner_user_id": str(nexus.owner_user_id),
                    "mcp_url": origin + "/v1/mcp",
                    "bearer": credentials["client:nexus-owner"],
                    "connect": nexus.connect,
                    "admit": nexus.admit,
                    "processors": list(config.processors.nexus_model_processors),
                },
            }
            if nexus is not None and nexus.connect
            else {"kind": "Absent"}
        )
        rendered[args.output / "nexus/client.json"] = (
            json.dumps(nexus_config, indent=2) + "\n"
        )
        for machine, owner_home in homes.items():
            collector_homes = {}
            profiles = []
            client_lines = []
            for lane in config.lanes:
                if lane.machine != machine or lane.provider == "jarvis":
                    continue
                root = Path(owner_home) / (
                    f".{lane.provider}"
                    if lane.account.endswith("-personal")
                    else f".{lane.account}"
                )
                collector_homes[lane.account] = {
                    "provider": lane.provider,
                    "state_root": str(root),
                    "codex_endpoint": (
                        str(root / "app-server-control/app-server-control.sock")
                        if lane.provider == "codex"
                        else None
                    ),
                }
                variable = (
                    "JARVIS_MEMORY_"
                    + lane.account.upper().replace("-", "_")
                    + "_BEARER"
                )
                profiles.append(
                    {
                        "account": lane.account,
                        "provider": lane.provider,
                        "state_root": str(root),
                        "connect": lane.connect,
                        "bearer_env": variable,
                        "url": origin + "/v1/mcp",
                    }
                )
                if lane.connect:
                    client_lines.append(
                        "export "
                        + variable
                        + "="
                        + credentials[f"client:{machine}:{lane.account}"]
                    )
            collector = CollectorConfig.model_validate_json(
                json.dumps(
                    {
                        "machine": machine,
                        "service_url": origin,
                        "homes": collector_homes,
                    }
                )
            )
            directory = args.output / machine
            rendered[directory / "collector.json"] = (
                collector.model_dump_json(indent=2) + "\n"
            )
            rendered[directory / "collector.env"] = (
                "export JARVIS_MEMORY_CAPTURE_BEARER="
                + credentials[f"capture:{machine}"]
                + "\n"
            )
            rendered[directory / "clients.env"] = "".join(
                line + "\n" for line in client_lines
            )
            rendered[directory / "profiles.json"] = (
                json.dumps(profiles, indent=2) + "\n"
            )
        # Validate the whole bundle before changing its one credential source.
        install(
            args.credentials, json.dumps(credentials, sort_keys=True, indent=2) + "\n"
        )
        for path, value in rendered.items():
            install(path, value)
    except (OSError, ValueError, KeyError, TypeError):
        parser.exit(1, "invalid memory deployment inputs; no credentials are printed\n")
    print("rendered the validated private memory deployment bundle")


if __name__ == "__main__":
    main()
