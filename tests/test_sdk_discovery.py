#!/usr/bin/env python3
"""Exercise SDK discovery using only temporary configuration and SDK fixtures."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[1]
CMAKE = sys.argv.pop(1) if len(sys.argv) > 1 else shutil.which("cmake")


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cmacros sdk discovery ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.config = self.root / "config"
        self.settings_dir = self.config / "cwhip"
        self.settings_dir.mkdir(parents=True)
        self.home.mkdir()
        self.new = self.settings_dir / "sdk.toml"
        self.legacy = self.settings_dir / "settings.toml"
        self.sdk = self.make_sdk("selected SDK")
        self.other = self.make_sdk("ordinary SDK")
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.config), CWHIP_SDK="",
                        _PROJECT_NAME="")
        self.env.pop("Cwhip_DIR", None)
        self.env.pop("CMAKE_PREFIX_PATH", None)

    def make_sdk(self, name):
        prefix = self.root / name
        package = prefix / "lib" / "cmake" / "Cwhip"
        package.mkdir(parents=True)
        (package / "CwhipConfigVersion.cmake").write_text(
            'set(PACKAGE_VERSION "0.0.1")\n'
            'set(PACKAGE_VERSION_EXACT TRUE)\n'
            'set(PACKAGE_VERSION_COMPATIBLE TRUE)\n', encoding="utf-8")
        (package / "CwhipConfig.cmake").write_text(
            'set(Cwhip_APPLICATION_OUTPUT_DIRECTORIES TRUE)\n'
            f'file(WRITE "${{CMAKE_BINARY_DIR}}/selected-sdk.txt" "{prefix}")\n'
            'function(cwhip_add_program name)\n'
            '  add_custom_target(${name})\n'
            '  set_target_properties(${name} PROPERTIES '
            'CWHIP_EXECUTABLE "${CMAKE_COMMAND}")\n'
            'endfunction()\n', encoding="utf-8")
        return prefix

    def write_prefix(self, path, prefix):
        path.write_text(f"sdk_prefix = {json.dumps(str(prefix))}\n",
                        encoding="utf-8")

    def helper(self):
        return subprocess.run([sys.executable, str(PROJECT / "scripts/sdk-prefix.py")],
                              env=self.env, capture_output=True, text=True)

    def assert_prefix(self, expected):
        result = self.helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(expected))

    def assert_error(self, filename="sdk.toml"):
        result = self.helper()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertIn(filename, result.stderr)
        self.assertIn("cannot read sdk_prefix", result.stderr)

    def configure(self, build="build"):
        return subprocess.run(
            [CMAKE, "-S", str(PROJECT), "-B", str(self.root / build),
             f"-DCMAKE_PREFIX_PATH={self.other}", "-DBUILD_TESTING=OFF"],
            env=self.env, capture_output=True, text=True)

    def assert_configured(self, expected, build="build"):
        result = self.configure(build)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / build / "selected-sdk.txt").read_text(),
                         str(expected))

    def test_new_over_legacy_and_preferences_rewrite(self):
        self.write_prefix(self.new, self.sdk)
        self.write_prefix(self.legacy, self.other)
        original = self.new.read_bytes()
        self.assert_prefix(self.sdk)
        self.assert_configured(self.sdk)
        self.legacy.write_text("[editor]\ntheme = 'dark'\n", encoding="utf-8")
        preferences = self.legacy.read_bytes()
        self.assert_prefix(self.sdk)
        self.assert_configured(self.sdk)
        self.assertEqual(self.new.read_bytes(), original)
        self.assertEqual(self.legacy.read_bytes(), preferences)

    def test_absent_new_legacy_compatibility(self):
        self.write_prefix(self.legacy, self.sdk)
        self.assert_prefix(self.sdk)
        self.assert_configured(self.sdk)
        self.assertFalse(self.new.exists())

    def test_missing_key_uses_ordinary_discovery_not_legacy(self):
        self.new.write_text("[editor]\ntheme = 'dark'\n", encoding="utf-8")
        self.write_prefix(self.legacy, self.sdk)
        self.assert_prefix("")
        self.assert_configured(self.other)

    def test_absent_configuration_uses_ordinary_discovery(self):
        self.assert_prefix("")
        self.assert_configured(self.other)
        self.assertEqual(list(self.settings_dir.iterdir()), [])

    def test_malformed_new_is_authoritative(self):
        self.new.write_text("sdk_prefix = [", encoding="utf-8")
        self.write_prefix(self.legacy, self.sdk)
        self.assert_error()
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sdk.toml", result.stderr)

    def test_invalid_prefixes_are_errors(self):
        for value in ("", "relative", str(self.root / "missing"), 12, [], {},
                      str(self.sdk) + "\n", str(self.sdk) + "\r",
                      str(self.sdk) + "\0", str(self.new)):
            with self.subTest(value=value):
                self.new.write_text(f"sdk_prefix = {json.dumps(value)}\n",
                                    encoding="utf-8")
                self.assert_error()

    def test_dangling_symlink_is_authoritative(self):
        self.new.symlink_to(self.root / "missing")
        self.write_prefix(self.legacy, self.sdk)
        self.assert_error()
        self.assertNotEqual(self.configure().returncode, 0)

    def test_directory_is_authoritative(self):
        self.new.mkdir()
        self.write_prefix(self.legacy, self.sdk)
        self.assert_error()

    @unittest.skipIf(os.geteuid() == 0, "root can read mode-000 files")
    def test_unreadable_new_is_authoritative(self):
        self.write_prefix(self.new, self.sdk)
        self.write_prefix(self.legacy, self.other)
        self.new.chmod(0)
        self.addCleanup(self.new.chmod, 0o600)
        self.assert_error()
        self.assertNotEqual(self.configure().returncode, 0)

    def test_malformed_legacy_is_error_only_without_new(self):
        self.legacy.write_text("sdk_prefix = [", encoding="utf-8")
        self.assert_error("settings.toml")
        self.write_prefix(self.new, self.sdk)
        self.assert_prefix(self.sdk)

    def test_env_bypasses_all_configuration(self):
        self.new.write_text("sdk_prefix = [", encoding="utf-8")
        self.env["XDG_CONFIG_HOME"] = "relative"
        self.env["CWHIP_SDK"] = str(self.sdk)
        self.assert_prefix(self.sdk)
        self.assert_configured(self.sdk)

    def test_config_home_selection(self):
        home_settings = self.home / ".config" / "cwhip"
        home_settings.mkdir(parents=True)
        self.write_prefix(home_settings / "sdk.toml", self.sdk)
        self.assert_prefix("")
        for value in ("", None):
            with self.subTest(xdg=value):
                if value is None:
                    self.env.pop("XDG_CONFIG_HOME", None)
                else:
                    self.env["XDG_CONFIG_HOME"] = value
                self.assert_prefix(self.sdk)
        self.env["XDG_CONFIG_HOME"] = "relative"
        result = self.helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not absolute", result.stderr)
        self.env["XDG_CONFIG_HOME"] = ""
        self.env.pop("HOME")
        self.assert_prefix("")

    def test_explicit_selection_clears_stale_cache_and_never_falls_back(self):
        self.assert_configured(self.other)
        self.write_prefix(self.new, self.sdk)
        self.assert_configured(self.sdk)
        empty_sdk = self.root / "empty SDK"
        empty_sdk.mkdir()
        self.write_prefix(self.new, empty_sdk)
        self.assertNotEqual(self.configure().returncode, 0)
        self.env["CWHIP_SDK"] = str(empty_sdk)
        self.assertNotEqual(self.configure().returncode, 0)

    def test_setup_uses_same_lookup_and_exports_sdk_for_project_shell(self):
        project = self.root / "project"
        scripts = project / "scripts"
        scripts.mkdir(parents=True)
        for name in ("setup", "sdk-prefix.py"):
            shutil.copy2(PROJECT / "scripts" / name, scripts / name)
        tools = self.root / "tools"
        tools.mkdir()
        log = self.root / "shell-sdk"
        cmake_log = self.root / "cmake-sdk"
        for name, destination in (("bash", log), ("cmake", cmake_log)):
            executable = tools / name
            executable.write_text(
                f'#!/bin/sh\nprintf "%s" "$CWHIP_SDK" > "{destination}"\n',
                encoding="utf-8")
            executable.chmod(0o755)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        self.write_prefix(self.new, self.sdk)
        self.write_prefix(self.legacy, self.other)
        setup = ["/bin/bash", str(scripts / "setup")]
        result = subprocess.run(setup, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.read_text(), str(self.sdk))
        self.assertEqual(cmake_log.read_text(), str(self.sdk))
        log.unlink()
        cmake_log.unlink()
        self.new.write_text("sdk_prefix = [", encoding="utf-8")
        result = subprocess.run(setup, env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("sdk.toml", result.stderr)
        self.assertFalse(log.exists())
        self.assertFalse(cmake_log.exists())
        self.env["CWHIP_SDK"] = str(self.other)
        result = subprocess.run(setup, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.read_text(), str(self.other))
        self.env["CWHIP_SDK"] = str(self.other) + "\n"
        result = subprocess.run(setup, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.read_text(), self.env["CWHIP_SDK"])


if __name__ == "__main__":
    unittest.main()
