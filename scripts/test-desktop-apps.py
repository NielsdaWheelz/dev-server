#!/usr/bin/env python3
"""Check reconciliation against an existing site config and a user's XFCE settings."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets" / "desktop-apps"


class DesktopAppsTests(unittest.TestCase):
    def test_site_defaults_preserve_other_keys_sections_and_comments(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "mimeapps.list"
            config.write_text(
                "# kept\n[Default Applications]\nvideo/mp4=old.desktop;\n"
                "audio/flac=music.desktop;\n[Added Associations]\nvideo/mp4=other.desktop;\n"
            )
            render = [sys.executable, ASSETS / "render-defaults.py", config, ASSETS / config.name]
            rendered = subprocess.check_output(render, text=True)
            expected = (
                "# kept\n[Default Applications]\nvideo/mp4=vlc.desktop;\n"
                "audio/flac=music.desktop;\ntext/html=firefox.desktop;\n"
                "x-scheme-handler/http=firefox.desktop;\nx-scheme-handler/https=firefox.desktop;\n"
                "video/x-matroska=vlc.desktop;\n[Added Associations]\nvideo/mp4=other.desktop;\n"
            )
            self.assertEqual(rendered, expected)
            config.write_text(rendered)
            self.assertEqual(subprocess.check_output(render, text=True), expected)

    def test_xfce_browser_survives_reapply(self):
        with tempfile.TemporaryDirectory() as directory:
            helpers = Path(directory) / "helpers.rc"
            render = [
                "bash", "-c", 'source "$1" && personal_arch_xfce_helpers "$2" "$3"', "test",
                ROOT / "lib/personal-arch.sh", helpers, ROOT / "assets/dotfiles/xfce4-helpers.rc",
            ]
            self.assertEqual(subprocess.check_output(render, text=True),
                             "TerminalEmulator=ghostty\nWebBrowser=firefox\n")
            helpers.write_text("# kept\nWebBrowser=chromium\nFileManager=Thunar\nTerminalEmulator=xterm\n")
            self.assertEqual(subprocess.check_output(render, text=True),
                             "# kept\nWebBrowser=chromium\nFileManager=Thunar\nTerminalEmulator=ghostty\n")

    def test_failed_render_never_installs_partial_output(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([
                "bash", "-c", """
                    source "$1"
                    workstation_declared_stage=$2
                    personal_arch_asset() { echo "$workstation_declared_stage"; }
                    ensure_directory_as_root() { return 0; }
                    python3() { echo partial; return 1; }
                    personal_arch_install_root_file() { touch "$workstation_declared_stage/installed"; }
                    if personal_arch_configure_gui_defaults; then exit 2; fi
                    test ! -e "$workstation_declared_stage/installed"
                """, "test", ROOT / "lib/personal-arch.sh", directory,
            ])
            self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
