#!/usr/bin/env python3
"""Black-box conformance tests for the installed-style cmacros executable."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


EXECUTABLE = Path(sys.argv[1]).resolve()


def invoke(*arguments, cwd=None, env=None):
    return subprocess.run(
        [str(EXECUTABLE), *map(str, arguments)],
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def test_cli_basics(root):
    result = invoke("--version")
    require(result.returncode == 0 and result.stdout == "cmacros: v1.0\n",
            f"version output mismatch: {result!r}")
    result = invoke("--help")
    require(result.returncode == 0 and "Usage: cmacros" in result.stdout,
            f"help output mismatch: {result!r}")
    result = invoke()
    require(result.returncode == 2 and "CMACRO0001" in result.stderr,
            f"missing-input diagnostic mismatch: {result!r}")
    result = invoke(root / "does not exist.cw")
    require(result.returncode == 1 and "CMACRO2000" in result.stderr,
            f"missing-file operational diagnostic mismatch: {result!r}")


def test_expansion_and_comments(root):
    source = root / "plain.cw"
    source.write_text(
        ".define VALUE {forward}\n"
        ".define pair(left, right) {@left-@right}\n"
        "@pair(\"left,side\", @VALUE)\n"
        "\"@VALUE // quoted text\" @VALUE\n"
        "\\@escaped // @VALUE must not expand\n"
        "/* hidden @VALUE\nstill hidden */tail\n",
        encoding="utf-8",
    )
    result = invoke(source)
    expected = ("\n\nleft,side-forward\n"
                "\"forward // quoted text\" forward\n"
                "@escaped \n \ntail\n")
    require(result.returncode == 0 and result.stdout == expected,
            f"expansion/comment mismatch:\nexpected={expected!r}\nactual={result!r}")


def test_forward_references_and_conditionals(root):
    source = root / "conditional.cw"
    source.write_text(
        ".if (LATE AND @NUMBER >= 7) {selected}\n"
        ".else (NOPE) {wrong}\n"
        ".else {fallback}\n"
        ".define LATE\n"
        ".define NUMBER {7}\n",
        encoding="utf-8",
    )
    result = invoke(source)
    require(result.returncode == 0 and "selected" in result.stdout and
            "wrong" not in result.stdout and "fallback" not in result.stdout,
            f"forward conditional failed: {result!r}")
    source.write_text(
        ".if (UNKNOWN OR NOT YES) {wrong}\n"
        ".else {right}\n"
        ".define YES\n",
        encoding="utf-8",
    )
    result = invoke(source)
    require(result.returncode == 0 and "right" in result.stdout and
            "wrong" not in result.stdout,
            f"undefined conditional names should be false: {result!r}")

    source.write_text(
        ".if (M2) {.define OUT {ready}}\n"
        ".if (M1) {.define M2}\n"
        ".define M1\n"
        "@OUT\n",
        encoding="utf-8",
    )
    result = invoke(source)
    require(result.returncode == 0 and "ready" in result.stdout and
            "@OUT" not in result.stdout,
            f"silent conditional definitions did not reach a fixed point: {result!r}")

    source.write_text(
        ".define echo(value) {@value}\n"
        ".define predicate(value) {1}\n"
        ".if (@echo(1) == 1) {condition macro call}\n"
        '.if (@predicate(")") AND @predicate("OR")) {quoted condition args}\n'
        '@echo("one\\ntwo")\n',
        encoding="utf-8",
    )
    result = invoke(source)
    require(result.returncode == 0 and
            result.stdout == ("\n\ncondition macro call\nquoted condition args\n"
                              "one\ntwo\n") and
            "condition macro call" in result.stdout,
            f"quoted argument escape or conditional macro expansion failed: {result!r}")


def test_cli_defines_and_output(root):
    source = root / "input with spaces.cw"
    output = root / "output with spaces.txt"
    source.write_text("@FROM_CLI()\n", encoding="utf-8")
    result = invoke("-D=FROM_CLI=hello", f"-o={output}", source)
    require(result.returncode == 0 and result.stdout == "" and
            output.read_text(encoding="utf-8") == "hello\n",
            f"CLI define/output path failed: {result!r}")
    output.write_text("preserve me", encoding="utf-8")
    source.write_text('before\n.error "stop now"\nafter\n', encoding="utf-8")
    result = invoke("-o", output, source)
    require(result.returncode == 1 and result.stdout == "" and
            output.read_text(encoding="utf-8") == "preserve me" and
            "CMACRO1003" in result.stderr and str(source) in result.stderr,
            f"failure changed output or omitted source diagnostic: {result!r}")
    temporary = Path(f"{output}.cmacros.tmp")
    temporary.write_text("stale temp", encoding="utf-8")
    source.write_text("complete\n", encoding="utf-8")
    result = invoke("-o", output, source)
    require(result.returncode == 1 and "CMACRO2008" in result.stderr and
            output.read_text(encoding="utf-8") == "preserve me" and
            temporary.read_text(encoding="utf-8") == "stale temp",
            f"output temporary collision changed existing files: {result!r}")
    temporary.unlink()

    source.write_text(".define IN_PLACE {complete}\n@IN_PLACE\n", encoding="utf-8")
    result = invoke("-o", source, source)
    require(result.returncode == 0 and source.read_text(encoding="utf-8") ==
            "\ncomplete\n",
            f"input/output alias was not safely replaced: {result!r}")


def test_import_search_and_cycles(root):
    main_dir = root / "main files"
    include_dir = root / "include files"
    main_dir.mkdir()
    include_dir.mkdir()
    imported = include_dir / "shared.txt"
    imported.write_text(".define IMPORTED {from import}\n", encoding="utf-8")
    source = main_dir / "main.cw"
    source.write_text('.import "shared"\n@IMPORTED\n', encoding="utf-8")
    result = invoke("-I", include_dir, source)
    require(result.returncode == 0 and "from import" in result.stdout,
            f"explicit import path or .txt fallback failed: {result!r}")

    first = main_dir / "first.cw"
    second = main_dir / "second.cw"
    first.write_text('.import "second.cw"\n', encoding="utf-8")
    second.write_text('.import "first.cw"\n', encoding="utf-8")
    result = invoke(first)
    require(result.returncode == 1 and "CMACRO2003" in result.stderr,
            f"import cycle not detected: {result!r}")

    chain_files = [root / f"import-depth-{index}.cw" for index in range(130)]
    for index, path in enumerate(chain_files[:-1]):
        path.write_text(f'.import "{chain_files[index + 1].name}"\n',
                        encoding="utf-8")
    chain_files[-1].write_text("", encoding="utf-8")
    result = invoke(chain_files[0])
    require(result.returncode == 1 and "CMACRO2002" in result.stderr,
            f"128-level import limit failed: {result!r}")

    env = os.environ.copy()
    env["MACRO_PATH"] = str(include_dir)
    source.write_text('.import "shared"\n', encoding="utf-8")
    result = invoke(source, env=env)
    require(result.returncode == 0, f"MACRO_PATH search failed: {result!r}")


def test_errors_and_limits(root):
    source = root / "error.cw"
    source.write_text(".define A {@B}\n.define B {@A}\n@A\n", encoding="utf-8")
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO1006" in result.stderr and
            str(source) in result.stderr,
            f"macro expansion cycle not diagnosed: {result!r}")
    source.write_text(".define one(a) {@a}\n@one()\n", encoding="utf-8")
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO1005" in result.stderr,
            f"macro arity mismatch not diagnosed: {result!r}")
    source.write_text(".define one(a,) {@a}\n", encoding="utf-8")
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO1000" in result.stderr,
            f"empty macro parameter was accepted: {result!r}")
    source.write_text('.define one(a) {@a}\n@one("\\xGG")\n',
                      encoding="utf-8")
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO1004" in result.stderr,
            f"malformed quoted argument escape was accepted: {result!r}")
    source.write_text(
        ".define one(a) {@a}\n.define one(b) {@b}\n",
        encoding="utf-8",
    )
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO1001" in result.stderr,
            f"conflicting macro parameter names were accepted: {result!r}")
    source.write_text(
        '.define bad {   .error "macro failure"}\n@bad\n',
        encoding="utf-8",
    )
    result = invoke(source)
    require(result.returncode == 1 and f"{source}:1:17:" in result.stderr and
            "expanded macro @bad" in result.stderr,
            f"macro source column or expansion note is missing: {result!r}")
    source.write_text(
        '.define bad { .error "condition failure"}\n.if (@bad) {unused}\n',
        encoding="utf-8",
    )
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO1003" in result.stderr and
            "in condition" in result.stderr,
            f"conditional macro expansion chain is missing: {result!r}")
    source.write_text("prefix\nmiddle\n.error \"failure\"\nsuffix\n",
                      encoding="utf-8")
    result = invoke(source)
    require(result.returncode == 1 and result.stdout == "" and
            f"{source}:3:1:" in result.stderr and "CMACRO1003" in result.stderr,
            f"source error emitted partial stdout: {result!r}")
    source.write_text(".if (YES &&) {invalid}\n", encoding="utf-8")
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO1009" in result.stderr and
            f"{source}:1:1:" in result.stderr,
            f"malformed conditional was not diagnosed at its source: {result!r}")
    source.write_text('"unterminated literal', encoding="utf-8")
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO1002" in result.stderr,
            f"unterminated quoted literal was not diagnosed: {result!r}")
    source.write_bytes(b"\xff")
    result = invoke(source)
    require(result.returncode == 1 and "CMACRO" in result.stderr,
            f"malformed UTF-8 did not produce an operational diagnostic: {result!r}")

    oversized = root / "too large.cw"
    oversized.write_bytes(b"x" * (16 * 1024 * 1024 + 1))
    result = invoke(oversized)
    require(result.returncode == 1 and "CMACRO2001" in result.stderr,
            f"16 MiB source limit failed: {result!r}")

    depth_source = root / "deep macros.cw"
    definitions = [
        f".define M{index} {{@M{index + 1}}}\n"
        for index in range(129)
    ]
    definitions.append(".define M129 {end}\n@M0\n")
    depth_source.write_text("".join(definitions), encoding="utf-8")
    result = invoke(depth_source)
    require(result.returncode == 1 and "CMACRO1002" in result.stderr,
            f"128-level expansion limit failed: {result!r}")

    too_much_work = root / "work limit.cw"
    too_much_work.write_bytes(b"x" * 2_000_001)
    result = invoke(too_much_work)
    require(result.returncode == 1 and "CMACRO2004" in result.stderr,
            f"2,000,000-work limit failed: {result!r}")

    too_much_output = root / "output limit.cw"
    too_much_output.write_text("😀" * 1_750_001, encoding="utf-8")
    result = invoke(too_much_output)
    require(result.returncode == 1 and "CMACRO2006" in result.stderr and
            result.stdout == "",
            f"7,000,000-byte output limit failed: {result!r}")

    nonconverging = root / "pass limit.cw"
    chain = [
        f".if (M{index}) {{.define M{index + 1}\nx}}\n"
        for index in range(255, -1, -1)
    ]
    chain.append(".define M0\n")
    nonconverging.write_text("".join(chain), encoding="utf-8")
    result = invoke(nonconverging)
    require(result.returncode == 1 and "CMACRO2007" in result.stderr and
            result.stdout == "",
            f"256-pass non-convergence limit failed: {result!r}")


def test_text_fidelity(root):
    source = root / "café 雪-crlf.cw"
    expected = "café 雪\r\nline two\n\n"
    source.write_bytes(expected.encode("utf-8"))
    result = subprocess.run(
        [str(EXECUTABLE), str(source)], capture_output=True, check=False
    )
    require(result.returncode == 0 and result.stdout == expected.encode("utf-8"),
            f"Unicode/newline fidelity failed: {result!r}")


def main():
    with tempfile.TemporaryDirectory(prefix="cmacros conformance ") as directory:
        root = Path(directory)
        test_cli_basics(root)
        test_expansion_and_comments(root)
        test_forward_references_and_conditionals(root)
        test_cli_defines_and_output(root)
        test_import_search_and_cycles(root)
        test_errors_and_limits(root)
        test_text_fidelity(root)
    print("cmacros CLI conformance tests passed")


if __name__ == "__main__":
    main()
