# Changelog

## Unreleased

- Migrate implementation integers to `int64` and require Cwhip SDK 0.0.2,
  ABI `numeric-v2`, without changing the macro input language.
- Identify the selected SDK prefix and give rebuild/reinstall instructions
  when an older SDK lacks the application-defaults helper.
- Inherit matching Cwhip SDK application install-prefix and build-type defaults
  before project initialization, preserving explicit settings and existing caches.
- Make setup's optional build mode an explicit override rather than defaulting
  to Debug. Require an SDK providing `cwhip_apply_application_defaults()`.

## 1.0

- Add the standalone Cwhip-based `cmacros` command-line processor.
- Add macro definitions and parameter substitution, imports, conditionals,
  source-aware diagnostics, resource limits, and atomic output replacement.
- Add an offline Python black-box conformance suite and CMake install target.
