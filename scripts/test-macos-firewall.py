#!/usr/bin/env python3
"""Exercise the native loader against isolated files and a fake pfctl."""

import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "assets/security/macos-firewall"
APPLE_ROOT = 'scrub-anchor "com.apple/*" all fragment reassemble\nanchor "com.apple/*" all'
APPLE_CONFIG = '''# preserve apple configuration and unrelated comments
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
dummynet-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"

# retain this footer
'''
GUARD = '[[ "$EUID" == 0 && "$(uname -s)" == Darwin && $# == 0 ]] || exit 64'


class FirewallTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="macos-firewall-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.config = self.directory / "pf.conf"
        self.config.write_text(APPLE_CONFIG)
        self.rules = self.directory / "anchor"
        self.rules.write_text("pass in quick all\n")
        identity = self.directory / "identity"
        identity.write_text(hashlib.sha256(self.rules.read_bytes()).hexdigest() + "\n")
        reference = self.directory / "reference"
        reference.write_text("123\n")
        self.state = {"root": APPLE_ROOT, "root_loads": 0, "anchor_loads": 0}
        self.state_file = self.directory / "state.json"
        fake = self.directory / "pfctl.py"
        fake.write_text('''import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
state = json.loads(p.read_text())
args = sys.argv[2:]
if args == ["-sr"]:
    print(state["root"])
elif args[:2] == ["-n", "-f"]:
    if state.get("invalid_config"): sys.exit(1)
elif args[0] == "-n":
    pass
elif args[0] == "-nv":
    print("pass in quick all")
elif args[0] == "-f":
    state["root_loads"] += 1
    if not state.get("ignore_hook"):
        state["root"] = 'scrub-anchor "com.apple/*" all fragment reassemble\\n'
        if 'anchor "dev-server"\\n' in pathlib.Path(args[1]).read_text():
            state["root"] += 'anchor "dev-server" all\\n'
        state["root"] += 'anchor "com.apple/*" all'
elif args == ["-a", "dev-server", "-sr"]:
    print("pass in quick all")
elif args[:3] == ["-a", "dev-server", "-f"]:
    state["anchor_loads"] += 1
elif args == ["-s", "References"]:
    print("123")
elif args == ["-s", "info"]:
    print("Status: Enabled for 0 days")
else:
    raise SystemExit("unexpected pfctl call: " + repr(args))
p.write_text(json.dumps(state))
''')
        source = HELPER.read_text()
        self.assertEqual(source.count(GUARD), 1)
        # The production root/platform guard stays intact; only this copy is runnable.
        fake_call = " ".join(map(shlex.quote, [sys.executable, str(fake), str(self.state_file)]))
        source = source.replace(GUARD, 'pfctl() { ' + fake_call + ' "$@"; }')
        for original, replacement in {
            "/etc/pf.conf": self.config,
            "/etc/pf.anchors/dev-server": self.rules,
            "/var/run/dev-server-firewall.sha256": identity,
            "/var/run/dev-server-firewall.token": reference,
        }.items():
            source = source.replace(original, str(replacement))
        self.helper = self.directory / "loader"
        self.helper.write_text(source)
        self.block = ('# >>> dev-server firewall >>>\nanchor "dev-server"\n'
                      f'load anchor "dev-server" from "{self.rules}"\n'
                      '# <<< dev-server firewall <<<\n')

    def run_loader(self):
        self.state_file.write_text(json.dumps(self.state))
        result = subprocess.run(["/bin/bash", str(self.helper)], capture_output=True, text=True)
        self.state = json.loads(self.state_file.read_text())
        return result

    def test_os_reset_is_repaired_and_repeat_is_inert(self):
        result = self.run_loader()
        self.assertEqual((result.returncode, result.stdout), (0, "changed\n"), result.stderr)
        self.assertEqual(self.config.read_text(), APPLE_CONFIG.replace(
            '\nanchor "com.apple/*"\n', '\n' + self.block + 'anchor "com.apple/*"\n'))
        self.assertIn('anchor "dev-server" all', self.state["root"])
        installed = self.config.stat()
        result = self.run_loader()
        self.assertEqual((result.returncode, result.stdout), (0, "unchanged\n"), result.stderr)
        self.assertEqual(self.state["root_loads"], 1)
        self.assertEqual((self.config.stat().st_ino, self.config.stat().st_mtime_ns),
                         (installed.st_ino, installed.st_mtime_ns))

    def test_successful_load_without_live_hook_is_failure(self):
        self.state["ignore_hook"] = True
        result = self.run_loader()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state["anchor_loads"], 0)
        self.assertNotIn("changed", result.stdout)

    def test_foreign_active_root_is_untouched(self):
        self.state["root"] += '\nanchor "foreign" all'
        result = self.run_loader()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_text(), APPLE_CONFIG)
        self.assertEqual(self.state["root_loads"], 0)

    def test_existing_live_hook_needs_no_foreign_root_reload(self):
        original = APPLE_ROOT + '\nanchor "dev-server" all\nanchor "foreign" all'
        self.state["root"] = original
        result = self.run_loader()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state["root"], original)
        self.assertEqual(self.state["root_loads"], 0)
        self.assertIn(self.block, self.config.read_text())

    def test_malformed_owned_markers_are_not_installed(self):
        malformed = APPLE_CONFIG + "# >>> dev-server firewall >>>\n"
        self.config.write_text(malformed)
        result = self.run_loader()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_text(), malformed)
        self.assertEqual(self.state["root_loads"], 0)

    def test_invalid_candidate_leaves_config_and_live_root_untouched(self):
        self.state["invalid_config"] = True
        result = self.run_loader()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_text(), APPLE_CONFIG)
        self.assertEqual(self.state["root"], APPLE_ROOT)
        self.assertEqual(self.state["root_loads"], 0)


if __name__ == "__main__":
    unittest.main()
