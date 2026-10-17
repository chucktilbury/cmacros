# Diagnostics and limits

Errors use the stable form

```text
cmacros: error[CMACROxxxx]: path:line:column: explanation
```

Locations refer to the original file and one-based line/column. When useful,
import and macro expansion notes follow the error. Startup/usage errors use
exit status 2; source, resource, and output failures use status 1; success,
help, and version use status 0. No ANSI color is required.

The code ranges follow the
[canonical Cwhip diagnostic contract](https://github.com/chucktilbury/cwhip/blob/master/doc/DIAGNOSTICS.md):
0001-0999 usage/startup, 1000-1999 source or language errors, 2000-2999
resources and configuration, 3000-3999 subprocess/transport, and 9000-9999
unexpected or cleanup failures. `cmacros` currently uses:

| Code(s) | Meaning |
| --- | --- |
| 0001 | Usage, missing input, or invalid command-line option |
| 1000-1009 | Invalid directive/definition, expansion depth or cycle, `.error`, macro call/arity, malformed conditional, or misplaced `.else` |
| 2000-2009 | Input/output failure, source/work/import/output limits, import lookup/cycle, or non-convergent passes |

The implementation has no subprocess or transport phase, so 3000-3999 is
reserved. No current `cmacros` path allocates codes in 9000-9999; that range
remains reserved for future unexpected-runtime or cleanup diagnostics.

The finite processing limits are deliberate safeguards:

| Resource | Limit |
| --- | ---: |
| One source file | 16 MiB |
| Import nesting | 128 |
| Macro/conditional expansion nesting | 128 |
| Work iterations | 2,000,000 per pass; 20,000,000 total |
| Expanded output | 7,000,000 bytes |
| Passes before non-convergence error | 256 |

Limits are checked before standard output is emitted and before an output
file is replaced. Limits and code assignments are part of the CLI contract;
the 3000-3999 and 9000-9999 ranges remain available for future errors without
renumbering existing codes.
