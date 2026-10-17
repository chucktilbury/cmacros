# Build and installation

## Requirements

- CMake 3.24+
- Python 3.11+ (used for SDK settings discovery and black-box tests)
- Cwhip SDK 0.0.1, including application output-directory support

The build uses Cwhip's `cwhip_add_program` and its static runtime. Macro
processing is implemented in `src/main.cw`; Python is used only as the test
driver and for safe TOML settings parsing.

## SDK discovery

The `CWHIP_SDK` environment variable takes precedence and must name the SDK
prefix. Otherwise, when present, `sdk_prefix` is read from
`$XDG_CONFIG_HOME/cwhip/settings.toml`, or
`$HOME/.config/cwhip/settings.toml` when `XDG_CONFIG_HOME` is unset. If the
setting is not configured, CMake uses normal package discovery. The project
requires the exact SDK version 0.0.1 and fails configuration if the
application output-directory capability is missing.

The repository's `scripts/setup` opens a project shell and configures the
`build` directory. It accepts `debug`, `release`, or `profile`; set
`CWHIP_SDK` first when the SDK is outside normal discovery.

## Build and test

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

The executable is written under `bin/`. CTest launches the actual Cwhip
executable through `tests/test_cli.py` and installs/relocates it in a temporary
prefix through `tests/test_install.py`. It also verifies the 16 preserved
upstream examples using `examples/run_examples.py`; see
[the examples guide](../examples/README.md). The suite does not fetch
dependencies or access the network.

## Install and relocate

```sh
cmake --install build --prefix /tmp/cmacros-install
/tmp/cmacros-install/bin/cmacros --version
```

The CLI is installed as a single executable at `bin/cmacros`. It has no
runtime dependency on the source or build tree. Relocating the install prefix
does not change its behavior.
