# cmacros

`cmacros` is a standalone command-line macro processor implemented in Cwhip.
It reads one UTF-8 source file, expands macros and directives in memory, then
writes the completed result to standard output or a selected file. The
processor does not invoke a shell, compiler, or other subprocess.

## Build

The project requires CMake 3.24 or newer, Python 3.11 or newer, and the
Cwhip 0.0.2 SDK with ABI `numeric-v2`. Point `CWHIP_SDK` at an SDK installation
if it is not in the normal CMake package search path. Otherwise CMake reads
`sdk_prefix` from
`$XDG_CONFIG_HOME/cwhip/sdk.toml` (or `$HOME/.config/cwhip/sdk.toml` when
`XDG_CONFIG_HOME` is unset or empty). Only when `sdk.toml` is absent does it
consult the legacy `settings.toml` in that same directory.
The SDK must provide `cwhip_apply_application_defaults()`. Fresh builds inherit
the matching SDK's registered application install prefix and build type;
explicit CMake options, environment choices, and existing caches take precedence.

```sh
cmake -S . -B build
cmake --build build
ctest --test-dir build --output-on-failure
cmake --install build --prefix "$HOME/.local"
```

The build places the executable at `bin/cmacros`. The install target installs
it as `bin/cmacros` under the chosen prefix. See [doc/BUILD.md](doc/BUILD.md)
for SDK discovery and install details.

## Usage

```text
cmacros [options] input
```

```sh
cmacros source.c
cmacros -I include -DPLATFORM=unix -o generated.c source.c
MACRO_PATH=shared:vendor cmacros --include=local source.c
```

`-I DIR` adds import directories in the order supplied; a colon-separated
value is also accepted. `-D NAME[=VALUE]` defines a macro before reading the
input; an omitted value is empty. `-o FILE` stages output beside the
destination and replaces it only after successful processing. Without `-o`,
the completed result is written to standard output. `--help` and `--version`
print to standard output. The legacy `-v N` option is accepted and ignored.
See [doc/LANGUAGE.md](doc/LANGUAGE.md) for the language contract and
[doc/DIAGNOSTICS.md](doc/DIAGNOSTICS.md) for errors and processing limits.

## Original examples

The original macros repository's 16 passing examples and import/support
files are preserved in [`examples/original-passing`](examples/original-passing).
Run one with `bin/cmacros examples/original-passing/define.txt`, or check all
expected outputs with `python3 examples/run_examples.py`. The suite also runs
through CTest. See [examples/README.md](examples/README.md) for provenance,
expected behavior, and comparison rules.

## Example

```c
.define GREETING {"Hello, @who!"}
.define who {world}
@GREETING

.if (WINDOWS OR @PLATFORM == 2) {
platform-specific code
}
.else {
portable code
}
```

Macro references are expanded on later passes, so ordinary forward
definitions work. Unresolved `@NAME` references in output text are preserved;
unresolved names in conditions are false. This behavior is intentionally
different from a C preprocessor: `cmacros` implements only the directives and
substitution rules documented for this tool.

## Project status

This is a standalone CLI milestone. Compiler integration, GUI support, binary
distribution packages, and icons are out of scope.
