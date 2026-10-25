#!/usr/bin/env python3
"""Expand current Cwhip syntax, compile it with the selected SDK, and run it."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


EXAMPLES = Path(__file__).resolve().parent.parent / "examples"


def main():
    executable, cmake, sdk = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="cmacros Cwhip output ") as directory:
        root = Path(directory)
        env = dict(os.environ, MACRO_PATH="", HOME=str(root / "home"),
                   XDG_CONFIG_HOME=str(root / "config"), CWHIP_SDK=sdk)
        (root / "home").mkdir()
        (root / "config").mkdir()

        def run(command):
            result = subprocess.run(command, env=env, capture_output=True,
                                    check=False, timeout=120)
            if result.returncode != 0:
                raise AssertionError(
                    f"{command!r} failed ({result.returncode}):\n"
                    f"{result.stdout.decode('utf-8', errors='replace')}\n"
                    f"{result.stderr.decode('utf-8', errors='replace')}")
            return result

        result = run([executable, str(EXAMPLES / "cwhip-syntax.txt")])
        expected = (EXAMPLES / "cwhip-syntax.cw").read_bytes()
        if result.stdout != expected or result.stderr:
            raise AssertionError(f"Cwhip expansion mismatch: {result!r}")
        source = root / "source"
        source.mkdir()
        (source / "main.cw").write_bytes(result.stdout)
        (source / "CMakeLists.txt").write_text(
            "cmake_minimum_required(VERSION 3.24)\n"
            "project(cmacros_generated_syntax LANGUAGES C)\n"
            "find_package(Cwhip 0.0.2 EXACT CONFIG REQUIRED)\n"
            'cwhip_add_program(generated SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/main.cw")\n',
            encoding="utf-8",
        )
        build = root / "build"
        run([cmake, "-S", str(source), "-B", str(build),
             f"-DCMAKE_PREFIX_PATH={sdk}"])
        run([cmake, "--build", str(build)])
        result = run([str(build / "bin" / "generated")])
        if result.stdout != b"42\n42\n" or result.stderr:
            raise AssertionError(f"generated Cwhip execution mismatch: {result!r}")
    print("cmacros generated Cwhip syntax test passed")


if __name__ == "__main__":
    main()
