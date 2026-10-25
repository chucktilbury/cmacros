# cmacros

`cmacros` is a standalone command-line macro processor implemented in Cwhip.
This directory contains the implementation in `src/`, regression tests in
`tests/`, macro examples in `examples/`, and build helpers in `scripts/`.

With a current Cwhip SDK installed, run `scripts/setup [--clean] [debug|release|profile]`
from the checkout, then `build` in the project shell. Use `rebuild` for a
clean-first build, or `clean` to remove generated outputs; exit the shell before
running setup again. See the build guide for SDK selection and installation.

- [Build and installation](doc/BUILD.md)
- [Command-line usage](doc/USAGE.md)
- [Macro language](doc/LANGUAGE.md)
- [Examples and generated Cwhip syntax](doc/EXAMPLES.md)
- [Diagnostics and processing limits](doc/DIAGNOSTICS.md)
