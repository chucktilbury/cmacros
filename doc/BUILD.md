# Build and installation

## Requirements

- CMake 3.24+
- Python 3.11+ (used for SDK configuration discovery and black-box tests)
- Cwhip SDK 0.0.1, including application output-directory support and
  `cwhip_apply_application_defaults()`

The build uses Cwhip's `cwhip_add_program` and its static runtime. Macro
processing is implemented in `src/main.cw`; Python is used only as the test
driver and for safe TOML configuration parsing.

## SDK discovery

The nonempty `CWHIP_SDK` environment variable takes precedence and bypasses
configuration parsing. Otherwise the top-level `sdk_prefix` is read from
`$XDG_CONFIG_HOME/cwhip/sdk.toml`, or `$HOME/.config/cwhip/sdk.toml` when
`XDG_CONFIG_HOME` is unset or empty. A nonempty `XDG_CONFIG_HOME` must be
absolute and is exclusive: lookup never also searches `HOME`.

Only an absent `sdk.toml` permits lookup in the legacy `settings.toml` in the
same directory. A present SDK file is authoritative, even if it has no
`sdk_prefix` key (which selects ordinary CMake discovery). Malformed or
unreadable files and invalid prefixes fail configuration without falling back.
The configured prefix must be a nonempty string naming an absolute, existing
directory, without NUL, CR, or LF characters:

```toml
sdk_prefix = "/absolute/path/to/cwhip-sdk"

[applications]
install_prefix = "/absolute/path/to/application/install"
build_type = "RelWithDebInfo"
```

Discovery is read-only and never rewrites or migrates user configuration.
SDK installation registers its prefix in `sdk.toml`, separately from the
editor/debugger preferences in `settings.toml`; rewriting those preferences
cannot change SDK discovery once `sdk.toml` exists. If neither file specifies
a prefix, CMake uses normal package discovery. An explicitly selected SDK is
required to work: it cannot silently fall back to another SDK or a cached
`Cwhip_DIR` from an earlier configuration. The project
requires the exact SDK version 0.0.1 and fails configuration if the
application output-directory capability or application-defaults helper is missing.

## Application defaults

SDK discovery, `find_package(Cwhip ...)`, and
`cwhip_apply_application_defaults()` run before `project()`. The shared SDK
helper seeds `CMAKE_INSTALL_PREFIX` and `CMAKE_BUILD_TYPE` from `[applications]`
in `sdk.toml` only for the matching selected SDK and absent cache entries.
Explicit `-D` values (including `/usr/local` and an empty build type),
`CMAKE_INSTALL_PREFIX`/`CMAKE_BUILD_TYPE` environment choices, and existing
cache values take precedence. Defaults are not read from legacy `settings.toml`.
The `CMAKE_INSTALL_PREFIX` environment override requires CMake 3.29 or newer;
with older CMake versions, use `-DCMAKE_INSTALL_PREFIX=...` instead.

The SDK installer registers these defaults from its actual installation
prefix and build configuration; `DESTDIR` staging does not register staged
paths. Consumers do not share the SDK build directory or inherit arbitrary
compiler flags. cmacros never installs into the SDK during configuration.

The repository's `scripts/setup` opens a project shell and configures the
`build` directory. With no argument it inherits the SDK default or retains the
cached build type. Explicit `debug`, `release`, or `profile` arguments pass
`Debug`, `Release`, or `RelWithDebInfo` as overrides; set `CWHIP_SDK` first when
the SDK is outside normal discovery. The shell exports the configured type as
`CWHIP_BUILD_TYPE` and its lowercase mode as `_BUILD_TYPE` (`default` when empty).

## Build and test

```sh
cmake -S . -B build
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

The executable is written under `bin/`. CTest launches the actual Cwhip
executable through `tests/test_cli.py` and installs/relocates it in a temporary
prefix through `tests/test_install.py`. It also verifies the 16 preserved
upstream examples using `examples/run_examples.py`; see
[the examples guide](../examples/README.md). The suite does not fetch
dependencies or access the network.

Run the isolated SDK discovery regressions without an installed SDK using
`python3 tests/test_sdk_discovery.py`. These cover the helper, CMake selection
and cache handling, and project-shell setup without touching user configuration.

## Install and relocate

```sh
cmake --install build --prefix /tmp/cmacros-install
/tmp/cmacros-install/bin/cmacros --version
```

The CLI is installed as a single executable at `bin/cmacros`. It has no
runtime dependency on the source or build tree. Relocating the install prefix
does not change its behavior.
