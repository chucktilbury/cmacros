#!/usr/bin/env python3
"""Verify all preserved upstream examples against reviewed semantic output."""

import argparse
import difflib
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent


def semantic_lines(text):
    """Ignore blank lines and boundary whitespace, but retain line order/content."""
    return [line.strip() for line in text.splitlines() if line.strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", nargs="?", type=Path,
                        default=ROOT.parent / "bin" / "cmacros")
    args = parser.parse_args()
    executable = args.executable.resolve()
    sources = sorted((ROOT / "original-passing").glob("*.txt"))
    expected_dir = ROOT / "expected"
    expected_names = {path.stem for path in expected_dir.glob("*.out")}
    source_names = {path.stem for path in sources}
    if not sources or expected_names != source_names:
        print("FAIL: example inputs and expected outputs must match exactly; "
              f"missing={sorted(source_names - expected_names)}, "
              f"extra={sorted(expected_names - source_names)}", file=sys.stderr)
        return 1

    env = os.environ.copy()
    env.pop("MACRO_PATH", None)
    failed = 0
    for source in sources:
        try:
            expected = (expected_dir / f"{source.stem}.out").read_text(
                encoding="utf-8")
            result = subprocess.run(
                [str(executable), str(source)], cwd=ROOT, env=env,
                capture_output=True, text=True, encoding="utf-8", timeout=30,
                check=False,
            )
            if result.returncode != 0 or result.stderr:
                print(f"FAIL {source.name}: exit={result.returncode}, "
                      f"stderr={result.stderr!r}", file=sys.stderr)
                failed += 1
                continue
            actual_lines = semantic_lines(result.stdout)
            expected_lines = semantic_lines(expected)
            if actual_lines != expected_lines:
                difference = "\n".join(difflib.unified_diff(
                    expected_lines, actual_lines, fromfile="expected",
                    tofile="actual", lineterm=""))
                print(f"FAIL {source.name}:\n{difference}", file=sys.stderr)
                failed += 1
                continue
        except (OSError, UnicodeError, subprocess.TimeoutExpired) as error:
            print(f"FAIL {source.name}: {error}", file=sys.stderr)
            failed += 1
            continue
        print(f"PASS {source.name}")
    print(f"{len(sources)} examples: {len(sources) - failed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
