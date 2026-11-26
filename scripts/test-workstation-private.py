#!/usr/bin/env python3
"""Exercise host binding, repeat installs and first-login display restoration."""

import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


helper = Path(__file__).with_name("restore-workstation-private")
restore = runpy.run_path(str(helper))


class RestoreTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.memory = {"collector.json": json.dumps({"machine": "desktop"}),
                       "collector.env": "a\r\n", "clients.env": "b\n", "profiles.json": "[]"}
        for name, value in self.memory.items():
            path = self.source / name
            path.write_bytes(value.encode())
            path.chmod(0o600)

    def receive(self, layout=None):
        with contextlib.redirect_stdout(io.StringIO()):
            restore["receive"]("desktop", self.memory, layout, self.root, self.root)

    def test_complete_idempotent_bundle_and_preserved_display(self):
        self.assertEqual(restore["load_bundle"](self.source), self.memory)
        with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 1)):
            self.receive('[{"name":"outputs"}]')
        self.receive("[]")
        installed = self.root / "secrets/memory/bundle/desktop"
        self.assertEqual(restore["load_bundle"](installed), self.memory)
        self.assertEqual((self.root / ".config/kwinoutputconfig.json").read_text(), '[{"name":"outputs"}]')
        self.memory["collector.env"] = "different"
        with self.assertRaisesRegex(SystemExit, "differs"):
            self.receive()
        self.assertEqual((installed / "collector.env").read_bytes(), b"a\r\n")

    def test_cli_transfers_to_matching_checkout_with_pinned_ssh_options(self):
        checkout = self.root / "Projects/dev-server"
        (checkout / "scripts").mkdir(parents=True)
        shutil.copy2(helper, checkout / "scripts" / helper.name)
        target = checkout / "workstation"
        target.write_text('#!/bin/sh\n[ "$1" = target ] && echo desktop\n')
        target.chmod(0o700)
        (checkout / ".gitignore").write_text("secrets/\n")
        subprocess.run(["git", "init", "-q", checkout], check=True)
        commands = self.root / "bin"
        commands.mkdir()
        # Run the actual receiver over a local pipe with dummy inputs. No real
        # ssh connection or workstation identity is used by this fixture.
        ssh = commands / "ssh"
        ssh.write_text('#!/bin/sh\ncase "$*" in *StrictHostKeyChecking=yes*) ;; *) exit 1;; esac\n'
                       'while [ "$#" -gt 1 ]; do shift; done\nexec sh -c "$1"\n')
        ssh.chmod(0o700)
        identity = commands / "id"
        identity.write_text('#!/bin/sh\n[ "$1" = -un ] && echo nnandal\n')
        identity.chmod(0o700)
        env = dict(os.environ, HOME=str(self.root), PATH=str(commands) + os.pathsep + os.environ["PATH"])
        proc = subprocess.run([helper, "desktop", self.source], env=env, capture_output=True, check=True)
        self.assertEqual(proc.stdout, b"memory bundle ready\n")
        self.assertEqual(restore["load_bundle"](checkout / "secrets/memory/bundle/desktop"), self.memory)

    def test_wrong_local_bundle_and_wrong_remote_receive_no_secrets(self):
        for machine, observed in (("arch", "arch"), ("desktop", "arch")):
            with self.subTest(machine=machine), patch("sys.argv", [str(helper), machine, str(self.source)]), \
                    patch("subprocess.check_output", return_value=observed + "\n") as probe, \
                    patch("subprocess.run") as send, self.assertRaises(SystemExit):
                try:
                    restore["main"]()
                finally:
                    send.assert_not_called()
                    if machine == "arch":
                        probe.assert_not_called()
                    else:
                        self.assertIn("StrictHostKeyChecking=yes", probe.call_args.args[0])

    def test_extra_private_file_rejected_and_running_plasma_is_preserved(self):
        (self.source / "server.json").write_text("{}")
        with self.assertRaisesRegex(SystemExit, "exactly four"):
            restore["load_bundle"](self.source)
        with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 0)), \
                self.assertRaisesRegex(SystemExit, "before starting"):
            self.receive("[]")
        self.assertFalse((self.root / ".config/kwinoutputconfig.json").exists())


if __name__ == "__main__":
    unittest.main()
