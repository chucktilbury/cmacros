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
        self.env.pop("CMAKE_INSTALL_PREFIX", None)
        self.env.pop("CMAKE_BUILD_TYPE", None)

    def make_sdk(self, name):
        prefix = self.root / name
        package = prefix / "lib" / "cmake" / "Cwhip"
        package.mkdir(parents=True)
        (package / "CwhipConfigVersion.cmake").write_text(
            'set(PACKAGE_VERSION "0.0.2")\n'
            'if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)\n'
            '  set(PACKAGE_VERSION_EXACT TRUE)\n'
            '  set(PACKAGE_VERSION_COMPATIBLE TRUE)\n'
            'endif()\n', encoding="utf-8")
        (package / "CwhipConfig.cmake").write_text(
            'set(Cwhip_APPLICATION_OUTPUT_DIRECTORIES TRUE)\n'
            'set(Cwhip_SDK_ABI "numeric-v2")\n'
            f'set(Cwhip_PREFIX "{prefix}")\n'
            f'file(WRITE "${{CMAKE_BINARY_DIR}}/selected-sdk.txt" "{prefix}")\n'
            'function(cwhip_add_program name)\n'
            '  add_custom_target(${name})\n'
            '  set_target_properties(${name} PROPERTIES '
            'CWHIP_EXECUTABLE "${CMAKE_COMMAND}")\n'
            'endfunction()\n'
            'include("${CMAKE_CURRENT_LIST_DIR}/ApplicationDefaults.cmake")\n',
            encoding="utf-8")
        # Stand-in for the SDK-owned helper: enforce the consumer call order.
        (package / "ApplicationDefaults.cmake").write_text(
            'function(cwhip_apply_application_defaults)\n'
            '  if(DEFINED PROJECT_NAME OR CMAKE_C_COMPILER_LOADED)\n'
            '    message(FATAL_ERROR "Application defaults must precede project()")\n'
            '  endif()\n'
            '  if(NOT DEFINED CMAKE_INSTALL_PREFIX AND "$ENV{CMAKE_INSTALL_PREFIX}" STREQUAL "")\n'
            f'    set(CMAKE_INSTALL_PREFIX "{self.root}/applications" CACHE PATH "")\n'
            '  endif()\n'
            '  get_property(cached CACHE CMAKE_BUILD_TYPE PROPERTY TYPE SET)\n'
            '  if(NOT cached AND NOT CMAKE_CONFIGURATION_TYPES)\n'
            '    if(DEFINED ENV{CMAKE_BUILD_TYPE})\n'
            '      set(value "$ENV{CMAKE_BUILD_TYPE}")\n'
            '    else()\n'
            '      set(value "RelWithDebInfo")\n'
            '    endif()\n'
            '    set(CMAKE_BUILD_TYPE "${value}" CACHE STRING "")\n'
            '  endif()\n'
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

    def configure(self, build="build", extra=()):
        return subprocess.run(
            [CMAKE, "-S", str(PROJECT), "-B", str(self.root / build),
             f"-DCMAKE_PREFIX_PATH={self.other}", "-DBUILD_TESTING=OFF", *extra],
            env=self.env, capture_output=True, text=True)

    def assert_configured(self, expected, build="build", extra=()):
        result = self.configure(build, extra)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / build / "selected-sdk.txt").read_text(),
                         str(expected))

    def assert_cache(self, prefix, build_type, build="build"):
        cache = (self.root / build / "CMakeCache.txt").read_text()
        self.assertIn(f"CMAKE_INSTALL_PREFIX:PATH={prefix}\n", cache)
        self.assertIn(f"CMAKE_BUILD_TYPE:STRING={build_type}\n", cache)

    def test_defaults_are_applied_before_project(self):
        self.assert_configured(self.other)
        self.assert_cache(self.root / "applications", "RelWithDebInfo")

    def test_numeric_abi_is_required_without_fallback(self):
        config = self.sdk / "lib/cmake/Cwhip/CwhipConfig.cmake"
        original = config.read_text()
        self.write_prefix(self.new, self.sdk)
        for abi in (None, "legacy", ""):
            declaration = "" if abi is None else f'set(Cwhip_SDK_ABI "{abi}")\n'
            config.write_text(original.replace(
                'set(Cwhip_SDK_ABI "numeric-v2")\n', declaration))
            for explicit in (False, True):
                with self.subTest(abi=abi, explicit=explicit):
                    self.env["CWHIP_SDK"] = str(self.sdk) if explicit else ""
                    result = self.configure(f"abi-{abi}-{explicit}")
                    self.assertNotEqual(result.returncode, 0)
                    diagnostic = " ".join(result.stderr.split())
                    self.assertIn(str(self.sdk), diagnostic)
                    self.assertIn("Cwhip_SDK_ABI=numeric-v2", diagnostic)
                    self.assertIn("Rebuild and reinstall", diagnostic)
                    self.assertIn("CWHIP_SDK", diagnostic)

    def test_old_sdk_version_is_rejected_without_fallback(self):
        version = self.sdk / "lib/cmake/Cwhip/CwhipConfigVersion.cmake"
        version.write_text(version.read_text().replace("0.0.2", "0.0.1"))
        self.write_prefix(self.new, self.sdk)
        result = self.configure()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("0.0.2", result.stderr)
        self.assertIn("0.0.1", result.stderr)

    def test_explicit_and_cached_values_override_defaults(self):
        for index, (prefix, build_type) in enumerate((
                ("/usr/local", ""), (str(self.root / "explicit"), "Debug"),
                ("", ""))):
            with self.subTest(prefix=prefix, build_type=build_type):
                build = f"override-{index}"
                self.assert_configured(self.other, build, (
                    f"-DCMAKE_INSTALL_PREFIX={prefix}",
                    f"-DCMAKE_BUILD_TYPE={build_type}"))
                self.assert_cache(prefix, build_type, build)
                self.env["CMAKE_BUILD_TYPE"] = "Release"
                self.assert_configured(self.other, build)
                self.assert_cache(prefix, build_type, build)
                self.env.pop("CMAKE_BUILD_TYPE")

    def test_build_type_environment_including_empty(self):
        for index, value in enumerate(("Debug", "")):
            with self.subTest(value=value):
                self.env["CMAKE_BUILD_TYPE"] = value
                build = f"environment-{index}"
                self.assert_configured(self.other, build)
                self.assert_cache(self.root / "applications", value, build)

    def test_install_prefix_environment(self):
        version = subprocess.run([CMAKE, "--version"], capture_output=True,
                                 text=True, check=True).stdout.split()[2]
        if tuple(map(int, version.split(".")[:2])) < (3, 29):
            self.skipTest("CMAKE_INSTALL_PREFIX environment requires CMake 3.29+")
        self.env["CMAKE_INSTALL_PREFIX"] = str(self.root / "environment")
        self.assert_configured(self.other)
        self.assert_cache(self.root / "environment", "RelWithDebInfo")

    def test_missing_application_defaults_helper_is_actionable(self):
        package = self.sdk / "lib/cmake/Cwhip"
        config = package / "CwhipConfig.cmake"
        config.write_text(config.read_text().replace(
            'include("${CMAKE_CURRENT_LIST_DIR}/ApplicationDefaults.cmake")\n', ""))
        (package / "ApplicationDefaults.cmake").unlink()
        # A valid current SDK remains discoverable, but must not be a fallback.
        self.write_prefix(self.new, self.sdk)
        for explicit in (False, True):
            with self.subTest(explicit=explicit):
                if explicit:
                    self.env["CWHIP_SDK"] = str(self.sdk)
                build = f"missing-helper-{explicit}"
                result = self.configure(build)
                self.assertNotEqual(result.returncode, 0)
                diagnostic = " ".join(result.stderr.split())
                self.assertIn(str(self.sdk), diagnostic)
                self.assertIn("application-defaults capability", diagnostic)
                self.assertIn("cwhip_apply_application_defaults()", diagnostic)
                self.assertIn("Rebuild and reinstall an updated Cwhip SDK", diagnostic)
                self.assertIn("CWHIP_SDK", diagnostic)
                self.assertNotIn("Unknown CMake command", diagnostic)
                self.assertEqual(
                    (self.root / build / "selected-sdk.txt").read_text(),
                    str(self.sdk))

    def test_setup_modes_and_cached_shell_environment(self):
        project = self.root / "project"
        shutil.copytree(PROJECT / "scripts", project / "scripts")
        shutil.copy2(PROJECT / "CMakeLists.txt", project / "CMakeLists.txt")
        tools = self.root / "tools"
        tools.mkdir()
        log = self.root / "shell-type"
        shell = tools / "bash"
        shell.write_text(
            f'#!/bin/sh\nprintf "%s:%s" "$_BUILD_TYPE" "$CWHIP_BUILD_TYPE" > "{log}"\n')
        shell.chmod(0o755)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        self.write_prefix(self.new, self.sdk)
        for arguments, expected in (
                ((), "profile:RelWithDebInfo"), (("debug",), "debug:Debug"),
                ((), "debug:Debug"), (("release",), "release:Release"),
                (("profile",), "profile:RelWithDebInfo")):
            with self.subTest(arguments=arguments, expected=expected):
                result = subprocess.run(
                    ["/bin/bash", str(project / "scripts/setup"), *arguments],
                    env=self.env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(log.read_text(), expected)
        result = subprocess.run(
            [CMAKE, "-S", str(project), "-B", str(project / "build"),
             "-DCMAKE_BUILD_TYPE="], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run(
            ["/bin/bash", str(project / "scripts/setup")], env=self.env,
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(log.read_text(), "default:")

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
        (project / "build").mkdir()
        (project / "build/CMakeCache.txt").write_text("CMAKE_BUILD_TYPE:STRING=\n")
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
