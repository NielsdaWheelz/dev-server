#!/usr/bin/env python3
"""Optional macOS boundary proof: real native TUI, fixture-only UDS, no provider.

Run explicitly: python3 tests/codex-native.py /absolute/path/to/raw/codex
Not part of ./test: needs the native binary and macOS network isolation.
Terminal bytes are discarded; no prompt or model turn is submitted.
"""

import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import threading


def read_exact(connection, size):
    data = b""
    while len(data) < size:
        part = connection.recv(size - len(data))
        if not part:
            raise AssertionError("native client closed before initialize")
        data += part
    return data


def observe_initialize(listener):
    # The native automatic-discovery probe connects and closes without bytes.
    connection, _ = listener.accept()
    with connection:
        connection.settimeout(10)
        assert connection.recv(1) == b"", "missing native discovery probe"
    connection, _ = listener.accept()
    with connection:
        connection.settimeout(10)
        headers = b""
        while not headers.endswith(b"\r\n\r\n"):
            assert len(headers) < 8192, "oversized WebSocket handshake"
            headers += read_exact(connection, 1)
        key = next(line.split(b":", 1)[1].strip() for line in headers.split(b"\r\n")
                   if line.lower().startswith(b"sec-websocket-key:"))
        accept = base64.b64encode(hashlib.sha1(
            key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
        connection.sendall(b"HTTP/1.1 101 Switching Protocols\r\n"
                           b"Upgrade: websocket\r\nConnection: Upgrade\r\n"
                           b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        frame = read_exact(connection, 2)
        assert frame[0] == 0x81 and frame[1] & 0x80, "expected masked text frame"
        size = frame[1] & 0x7f
        if size == 126:
            size = struct.unpack("!H", read_exact(connection, 2))[0]
        elif size == 127:
            size = struct.unpack("!Q", read_exact(connection, 8))[0]
        assert size <= 65536, "oversized initialize frame"
        mask = read_exact(connection, 4)
        payload = read_exact(connection, size)
        message = json.loads(bytes(byte ^ mask[index % 4]
                                   for index, byte in enumerate(payload)))
        assert message["method"] == "initialize", "unexpected first RPC"
        assert message["params"]["clientInfo"]["name"] == "codex-tui", "not native TUI"
        # No response: deliberately stop before account reads or thread creation.


def main():
    if sys.platform != "darwin" or not Path("/usr/bin/sandbox-exec").exists():
        print("NOT_RUN native Codex attachment requires macOS network isolation")
        return 2
    if len(sys.argv) != 2 or not Path(sys.argv[1]).is_absolute():
        print("usage: python3 tests/codex-native.py /absolute/path/to/raw/codex", file=sys.stderr)
        return 64
    if not os.access(sys.argv[1], os.X_OK):
        print("NOT_RUN native Codex attachment requires an executable")
        return 2
    binary = Path(sys.argv[1]).resolve(strict=True)
    repo = Path(__file__).resolve().parents[1]
    helper = repo / "assets/codex/codex-shared.py"
    declaration = repo / "assets/codex/profiles.json"
    with tempfile.TemporaryDirectory(prefix="cdx-native-", dir="/tmp") as directory:
        home = Path(directory).resolve()
        env = {"HOME": str(home), "PATH": os.defpath + ":/opt/homebrew/bin:/usr/local/bin",
               "TERM": "xterm-256color", "TMPDIR": str(home)}
        (home / ".local/bin").mkdir(parents=True)
        (home / ".local/bin/codex").symlink_to(binary)
        policy = home / "network.sb"
        policy.write_text('(version 1) (allow default) (deny network*)\n'
                          '(allow network-outbound (remote unix-socket '
                          '(subpath (param "FIXTURE"))))\n')
        sandbox = ["/usr/bin/sandbox-exec", "-D", f"FIXTURE={home}", "-f", str(policy)]
        command = [sys.executable, str(helper), "--config", str(declaration), "--host", "macbook"]
        launcher = subprocess.run(command + ["launcher"], env=env, capture_output=True,
                                  timeout=10, check=True).stdout
        for name in (".codex", ".codex-work", ".codex-work2"):
            account = home / name
            account.mkdir(mode=0o700)
            (account / "config.toml").write_text(
                'check_for_update_on_startup = false\ncli_auth_credentials_store = "file"\n'
                '[analytics]\nenabled = false\n[otel]\nexporter = "none"\n'
                'trace_exporter = "none"\nmetrics_exporter = "none"\n')
        subprocess.run(command + ["install-discovery"], env=env, capture_output=True,
                       timeout=10, check=True)
        for name, profile in (("codex", "personal"), ("codex-work", "work"), ("codex-work2", "work2")):
            wrapper = home / name
            wrapper.write_bytes(launcher)
            wrapper.chmod(0o755)
            endpoint = home / ".local/run/codex-shared" / profile / "app-server.sock"
            endpoint.parent.mkdir(parents=True)
            with socket.socket(socket.AF_UNIX) as listener:
                listener.bind(str(endpoint))
                listener.listen()
                listener.settimeout(15)
                master, slave = pty.openpty()
                fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
                stopped = threading.Event()

                def discard_terminal():
                    while not stopped.is_set():
                        if select.select([master], [], [], 0.1)[0]:
                            try:
                                data = os.read(master, 65536)
                                if not data:
                                    return
                                if b"\x1b[6n" in data:
                                    os.write(master, b"\x1b[1;1R")
                            except OSError:
                                return

                reader = threading.Thread(target=discard_terminal)
                process = subprocess.Popen(sandbox + [str(wrapper)], env=env, cwd=home,
                                           stdin=slave, stdout=slave, stderr=slave,
                                           start_new_session=True)
                os.close(slave)
                reader.start()
                try:
                    observe_initialize(listener)
                finally:
                    # This exact process group belongs only to this fixture.
                    try:
                        try:
                            os.killpg(process.pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait(timeout=5)
                    finally:
                        stopped.set()
                        reader.join(timeout=2)
                        os.close(master)
            print(f"PASS native {name} discovery and TUI initialize")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError):
        print("FAIL native Codex attachment boundary (content discarded)", file=sys.stderr)
        sys.exit(1)
