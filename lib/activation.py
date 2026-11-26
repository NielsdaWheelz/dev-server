#!/usr/bin/env python3
"""One target-local native activation job and its private last-run result."""

import fcntl
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time


LABEL = "dev.niels.dev-server.activation"
UNIT = "dev-server-activation.service"


def save(path, report):
    temporary = path.with_suffix(".tmp")
    with open(temporary, "w", encoding="utf-8") as stream:
        json.dump(report, stream)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def environment():
    home = str(Path.home())
    values = {
        "HOME": home,
        "PATH": f"{home}/bin:{home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8",
    }
    for key in ("XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"):
        if key in os.environ:
            values[key] = os.environ[key]
    if sys.platform == "linux":
        values["XDG_RUNTIME_DIR"] = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        values["DBUS_SESSION_BUS_ADDRESS"] = f"unix:path={values['XDG_RUNTIME_DIR']}/bus"
    return values


def native(arguments):
    return subprocess.run(arguments, env=environment(), stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True, timeout=15, check=False)


def running():
    if sys.platform == "darwin":
        result = native(["launchctl", "print", f"gui/{os.getuid()}/{LABEL}"])
        if result.returncode == 113:
            return False
        if result.returncode != 0:
            return None
        return re.search(r"^\s*pid = [1-9][0-9]*\s*$", result.stdout, re.MULTILINE) is not None
    result = native(["systemctl", "--user", "show", UNIT, "--property=LoadState,ActiveState"])
    properties = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if properties.get("LoadState") == "not-found":
        return False
    if result.returncode != 0 or "ActiveState" not in properties:
        return None
    if properties["ActiveState"] in ("inactive", "failed"):
        return False
    return True


def check(path):
    # This owner writes its report before submitting a job, and never deletes it.
    if not path.exists():
        return 0
    report = json.loads(path.read_text(encoding="utf-8"))
    run_name = report["run"]
    if not isinstance(run_name, str) or not run_name.startswith("apply-") or Path(run_name).name != run_name:
        return 2
    previous = path.parent / run_name
    if report["state"] == "awaitingVerification":
        status = verify_after_exit(path, previous)
        if status is None:
            print(f"activation still completing; inspect {path} before retrying", file=sys.stderr)
            return 2
        return status
    if report["state"] != "finished" or report["exitCode"] not in (0, 1, 2):
        print(f"activation completion unresolved; inspect {path} before retrying", file=sys.stderr)
        return 2
    if sys.platform == "darwin":
        result = native(["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"])
        # An absent service can report ESRCH (3) or service not found (113).
        if result.returncode not in (0, 3, 113):
            return 2
    else:
        result = native(["systemctl", "--user", "stop", UNIT])
        if result.returncode not in (0, 5):
            return 2
    if previous.exists():
        shutil.rmtree(previous)
    return 0


def submit(stage, target):
    arguments = ["/usr/bin/env", "-i"]
    arguments.extend(f"{key}={value}" for key, value in environment().items())
    arguments.extend([sys.executable, str(stage / "activation.py"), "run", target, str(stage)])
    if sys.platform == "darwin":
        configuration = {
            "Label": LABEL, "ProgramArguments": arguments, "RunAtLoad": True,
            "KeepAlive": False, "WorkingDirectory": str(Path.home()),
            "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null",
        }
        definition = stage / "job.plist"
        with open(definition, "wb") as stream:
            plistlib.dump(configuration, stream)
        return native(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(definition)]).returncode
    return native(["systemd-run", "--user", "--unit", UNIT, "--collect", "--quiet", "--no-block",
                   "--property=Type=oneshot", "--property=Restart=no", "--", *arguments]).returncode


def finish(path, report, stage, status):
    try:
        shutil.rmtree(stage)
    except FileNotFoundError:
        pass
    except OSError:
        status = 1
        report["results"].append({"status": "ERROR", "subject": "activation cleanup",
                                  "detail": "run inputs could not be removed; completed work remains"})
    report.update(state="finished", exitCode=status)
    save(path, report)
    return status


def verify_after_exit(path, stage):
    # A returning caller and a later "check" may both observe the same handoff.
    with (path.parent / "activation.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return None
        report = json.loads(path.read_text(encoding="utf-8"))
        if report["run"] != stage.name:
            return 2
        if report["state"] == "finished":
            return report["exitCode"]
        if report["state"] != "awaitingVerification":
            return 2
        active = running()
        if active is True:
            return None
        if active is not False:
            return 2

        status = report["maintenanceExitCode"]
        rows = {row["subject"]: row for row in report["results"]}
        for command, expected in report.pop("expectedVersions", {}).items():
            subject = f"AI daemon {command}"
            row = rows[subject]
            try:
                probe = native(["/bin/bash", str(stage / "activation.sh"), "--version", command])
                actual = probe.stdout.strip() if probe.returncode == 0 else ""
            except (OSError, subprocess.TimeoutExpired):
                actual = ""
            if actual == expected:
                row["detail"] += f"; running {actual} verified after activation"
            else:
                detail = f"running {actual}" if actual else "daemon version unavailable"
                report["results"].append({"status": "ACTION", "subject": subject,
                                          "detail": f"{detail} after activation; expected {expected}"})
                if status == 0:
                    status = 2
        # A disconnect during cleanup can now finish from this report alone.
        report["maintenanceExitCode"] = status
        save(path, report)
        del report["maintenanceExitCode"]
        return finish(path, report, stage, status)


def apply(path, target, library):
    if check(path) != 0:
        return 2
    stage = Path(tempfile.mkdtemp(prefix="apply-", dir=path.parent))
    report = {"schemaVersion": 1, "run": stage.name, "target": target,
              "state": "running", "jobAccepted": False, "exitCode": None, "results": []}
    save(path, report)
    try:
        for name in ("common.sh", "ai-tools.sh", "activation.sh", "activation.py"):
            shutil.copyfile(library / name, stage / name)
        (stage / "results.jsonl").touch(mode=0o600)
    except OSError:
        report["results"].append({"status": "ERROR", "subject": "activation",
                                  "detail": "could not prepare activation inputs; no job submitted"})
        return finish(path, report, stage, 1)
    # From submission onward the native job or explicit repair owns the scratch.
    try:
        submitted = submit(stage, target)
    except FileNotFoundError:
        report["results"].append({"status": "ERROR", "subject": "activation",
                                  "detail": "native service tools are unavailable; no job submitted"})
        return finish(path, report, stage, 1)
    except (OSError, subprocess.TimeoutExpired):
        return 2
    if submitted != 0:
        return 2
    deadline = time.monotonic() + 1800
    startup_deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        observed = json.loads(path.read_text(encoding="utf-8"))
        if observed["run"] != stage.name:
            return 2
        if observed["state"] == "finished":
            return observed["exitCode"]
        if observed["state"] == "awaitingVerification":
            status = verify_after_exit(path, stage)
            if status is not None:
                return status
        elif not observed["jobAccepted"]:
            if time.monotonic() >= startup_deadline:
                return 2
        elif running() is False:
            observed = json.loads(path.read_text(encoding="utf-8"))
            if observed["run"] != stage.name or observed["state"] == "running":
                return 2
            continue
        time.sleep(1)
    # Bound observation only; never kill a still-running activation.
    return 2


def run(path, target, stage):
    report = json.loads(path.read_text(encoding="utf-8"))
    if report["run"] != stage.name or report["target"] != target:
        return 2
    report["jobAccepted"] = True
    save(path, report)
    result = subprocess.run(["/bin/bash", str(stage / "activation.sh"), "--worker", str(stage)],
                            env=environment(), cwd=Path.home(), stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    status = result.returncode
    with open(stage / "results.jsonl", encoding="utf-8") as stream:
        report["results"] = [json.loads(line) for line in stream]
    if status not in (0, 1, 2):
        report["results"].append({"status": "ACTION", "subject": "activation",
                                  "detail": "process stopped unexpectedly; inspect the result before retrying"})
        save(path, report)
        return 2
    if status == 1 and not any(row["status"] == "ERROR" for row in report["results"]):
        report["results"].append({"status": "ERROR", "subject": "activation",
                                  "detail": "activation process failed; inspect the result before retrying"})
    versions = stage / "versions"
    if sys.platform == "linux" and (status == 0 or versions.exists()):
        expected = dict(line.split("\t") for line in versions.read_text(encoding="utf-8").splitlines())
        successful = {row["subject"] for row in report["results"]
                      if row["status"] in ("UPDATED", "STARTED", "UP TO DATE")}
        if successful != {f"AI daemon {command}" for command in expected} or (not expected and status == 0):
            raise ValueError("incomplete daemon maintenance results")
        if expected:
            report.update(state="awaitingVerification", maintenanceExitCode=status, expectedVersions=expected)
            save(path, report)
            return status
    return finish(path, report, stage, status)


def main():
    os.umask(0o077)
    path = Path.home() / ".local/state/dev-server/apply.json"
    command = sys.argv[1:]
    if command == ["check"]:
        return check(path)
    if len(command) == 3 and command[0] == "apply" and command[1] in ("macbook", "arch", "desktop", "devbox"):
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        return apply(path, command[1], Path(command[2]))
    if len(command) == 3 and command[0] == "run" and command[1] in ("macbook", "arch", "desktop", "devbox"):
        return run(path, command[1], Path(command[2]))
    return 64


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        print("activation result unavailable; inspect ~/.local/state/dev-server/apply.json before retrying", file=sys.stderr)
        sys.exit(2)
