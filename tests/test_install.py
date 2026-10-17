#!/usr/bin/env python3
"""Install the built CLI, relocate its prefix, and exercise the installed app."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, check=False,
                          **kwargs)


def main():
    cmake = sys.argv[1]
    build_dir = Path(sys.argv[2])
    configuration = sys.argv[3]

    with tempfile.TemporaryDirectory(prefix="cmacros install relocation ") as temp:
        root = Path(temp)
        prefix = root / "initial prefix"
        install_command = [cmake, "--install", str(build_dir),
                           "--prefix", str(prefix)]
        if configuration:
            install_command.extend(["--config", configuration])
        result = run(install_command)
        if result.returncode != 0:
            raise AssertionError(f"install failed: {result.stderr}")

        relocated = root / "relocated prefix"
        shutil.move(str(prefix), str(relocated))
        executable = relocated / "bin" / "cmacros"
        result = run([str(executable), "--version"])
        if result.returncode != 0 or result.stdout != "cmacros: v1.0\n":
            raise AssertionError(f"relocated version check failed: {result!r}")

        source = root / "source with spaces.cw"
        source.write_text(".define VALUE {installed}\n@VALUE\n",
                          encoding="utf-8")
        result = run([str(executable), str(source)])
        if result.returncode != 0 or result.stdout != "\ninstalled\n":
            raise AssertionError(f"relocated processing failed: {result!r}")

    print("cmacros install/relocation test passed")


if __name__ == "__main__":
    main()
