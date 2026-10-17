# Original macros examples

`original-passing/` contains all **16** `.txt` files from
[`chucktilbury/macros`, `tests/passing`](https://github.com/chucktilbury/macros/tree/c777e0f7f3a60591ee599d093b63c18d3e05c145/tests/passing)
at commit `c777e0f7f3a60591ee599d093b63c18d3e05c145`. They are copied
byte-for-byte, including the import/support files. The upstream MIT license
and its 2025 Charles Tilbury attribution are retained in
`original-passing/LICENSE`.

## Run

From the cmacros repository root, after building:

```sh
# One example (imports resolve relative to its source file)
bin/cmacros examples/original-passing/import.txt
bin/cmacros examples/original-passing/test1.txt

# All examples, using the actual compiled executable
python3 examples/run_examples.py
# Or specify an installed/alternate executable:
python3 examples/run_examples.py /absolute/path/to/cmacros

# The same suite through CTest
ctest --test-dir build -R cmacros-original-examples --output-on-failure
```

The runner checks successful exit, empty stderr, and the ordered output lines
against checked-in files in `expected/`. It rejects missing or extra expected
files, launch/read errors, timeouts, diagnostics, and output differences.
`MACRO_PATH` is cleared for reproducible import lookup. It does not update or
generate expectations.

## Expected behavior and upstream differences

The upstream `tests/runtests.py` lists six entry points (`define`, `import`,
`define1`, `define2`, `arity`, `ifelse`), invokes the original `macros` with
`-i`, `-o`, and `-v0`, and checks only exit status. Although it imports
`filecmp`, it does not use it; there are **no golden outputs** in that suite.
This suite additionally runs `expand` and `expand1` (the eight entry points
previously smoke-tested during the Cwhip port), plus all eight remaining
files individually. Definition-only support files `test2` and `test3`
intentionally produce no nonblank output when run alone.

The checked-in expectations are semantic line transcripts reviewed against
the source bodies, parameter arguments, import order, and branch conditions,
not captured upstream golden files. For example:

| Examples | Expected effect |
| --- | --- |
| `arity`, `define1`, `define2`, `define` | Substitute arguments in order, keep numeric text, expand empty/ordinary macros |
| `expand`, `expand1` | Recursively substitute global and parameter references |
| `ifelse` | Keep the two defined-name branches, omit `name3` and fallback text |
| `import`, `import1`-`import3` | Emit nested before/after text in depth-first order |
| `inp1`, `inp2` | Select the undefined-name fallback, preserve `.nope` and unresolved `@number`, `@eight`, `@1` |
| `test1`-`test3` | Import definitions using `.txt` fallback; substitute `zoob`, `klap`, `flonk` into the nested call; select the true branch containing `102` |

No input compatibility edits were necessary. The runner uses cmacros'
positional input syntax instead of upstream `-i`; no `-v0` is needed.
Expectations follow the documented cmacros choices, particularly parameter
substitution, undefined-reference preservation, expansion inside quoted
output, and unknown-directive preservation, rather than reproduce original
implementation bugs.

For readability and to avoid treating legacy comment/indentation layout as
a byte-level compatibility promise, comparisons strip leading/trailing
whitespace from each line and discard blank lines. All remaining characters,
line order, duplicates, unresolved markers, and selected/omitted text must
match. The separate CLI conformance suite tests exact whitespace, Unicode,
and newline preservation; these examples do not replace it.
