# Language reference

This document defines the language accepted by the `cmacros` CLI. The
processor preserves UTF-8 text and line endings except where a directive,
comment, escape, or macro expansion changes them.

The macro input language is distinct from the Cwhip implementation language.
Braces still delimit `.define` bodies; they are not dictionary literals.
Replacement text that emits Cwhip must use current Cwhip syntax, such as
`return(value)`, `int64<int64>`, and `["key": value]`. Native C replacement
text retains its C syntax, including semicolons. See
[Examples](EXAMPLES.md) for an expansion that is compiled and run by CTest.

## Names and definitions

Names start with an ASCII letter or underscore and continue with ASCII
letters, digits, or underscores. Names are case-sensitive.

```text
.define NAME
.define NAME {replacement text}
.define NAME(first, second) {replacement text using @first and @second}
```

The braced replacement may span lines and contain nested braces. Quotes and
comments are recognized while locating the closing brace. A definition with
no body is an empty object-like macro. Parameterized definitions require a
braced body. Parameter names must be unique and non-empty. A repeated
definition is accepted only when its body, parameter names, and definition
kind match the existing definition; a conflicting definition is an error.

Use `@NAME` to expand an object-like macro and `@NAME(arguments)` to expand a
parameterized macro. A zero-parameter definition may be referenced with or
without `()`. Arguments are comma-separated; nested parentheses, brackets,
braces, and quoted strings protect commas. The number of arguments must match
the definition. Empty arguments can be written as `""`.

Quoted arguments have their surrounding quotes removed and common C escapes
decoded (`\\`, `\"`, `\'`, `\n`, `\r`, `\t`, `\b`, `\f`, `\v`, `\a`, `\e`,
and `\xHH`). An unquoted argument is trimmed at its ends but otherwise kept
verbatim. Other escaped characters lose the backslash; malformed hexadecimal
escapes are rejected. Substituted text is scanned recursively, so a parameter
may itself contain macro references.

Unresolved `@NAME` references in ordinary text are copied unchanged. In
macro bodies, references matching declared parameters substitute argument
text; other names use normal macro-reference resolution. Undefined names in
conditional expressions evaluate to false. Macro calls are expanded
recursively and detected cycles are errors.

## Imports

```text
.import "path"
.include "path"
```

Both directives insert and process another UTF-8 source file at that point.
If the requested path is relative, it is searched first relative to the file
containing the directive, then in `-I` directories, then in directories from
`MACRO_PATH`. The environment variable and `-I` use colon-separated
directories. If an exact candidate is absent, a `.txt` suffix is tried.
Search order is stable; the current directory as an independent search path,
the shell `PATH`, and recursive directory scans are not used. Canonical paths
are tracked to reject direct and indirect import cycles.

## Conditionals

```text
.if (expression) {text}
.else (expression) {text}
.else {fallback}
```

Conditions and bodies are required to be parenthesized and braced as shown.
Each conditional selects the first matching branch. A final `.else` without
an expression is the fallback. Conditional directives may be nested.

Names test whether a macro is defined: a defined name is true even when its
replacement is empty; an undefined name is false. `@NAME` evaluates the
expanded replacement: empty text and numeric zero are false, non-empty
non-numeric text is true. Decimal integer literals use the same zero/nonzero
truth rule. `true` and `false` are accepted case-insensitively.

The supported operators, from lowest to highest precedence, are:

| Precedence | Operators |
| --- | --- |
| 1 | `OR`, `\|\|` |
| 2 | `AND`, `&&` |
| 3 | `==`, `!=`, `EQ`, `NEQ` |
| 4 | `<`, `<=`, `>`, `>=`, `LT`, `LTE`, `GT`, `GTE` |
| unary | `!`, `NOT` |
| grouping | `( expression )` |

Operators are case-insensitive when written as words. Decimal operands are
compared as arbitrary-length signed integers. Other comparison operands are
compared by truth value (false before true), not lexically. All operands are
evaluated; logical operators do not short-circuit. Malformed expressions
produce source diagnostics rather than silently choosing a branch.

Macro definitions are retained across bounded repeated passes, allowing
forward references in ordinary text and conditions. Every pass processes the
original input and imported source snapshot. Processing stops only after two
successive outputs match and the latest pass added no definitions. Thus an
unchanged output does not hide a newly defined name that may select a branch
on the next pass. Definitions made in a selected body or imported file
participate in later passes.

## Comments, strings, and escapes

During text expansion, outside quoted literals, `//` comments run to (but do
not consume) the next line feed. `/* ... */` comments are replaced by one
space; any line feeds inside a block comment are preserved. An unterminated
block comment is an error. With `-k` / `--keep-comments`, those comment forms
are left in the output unchanged; recognition is not language-context
sensitive beyond the existing quoted-literal rules.

Single- and double-quoted literals protect comment openers and directive
syntax. Macro references inside a quoted literal are still expanded, matching
the selected cmacros substitution behavior. Backslash-escaped quote
characters do not end a literal. An unclosed quoted literal is an error.
`\@` emits a literal `@` and suppresses reference expansion for that marker.

## Other directives and output

`.error "message"` stops processing and reports the message as an error.
`.message "message"` writes a message to standard error and continues.
Unknown dot-prefixed text is preserved as ordinary output.

Input is fully processed before any result is written. When no input path is
given, or the path is `-`, the source is standard input (even with `-o`).
Standard output is empty on a processing error unless writing the completed
result there. For a real `-o` path, a sibling temporary file is written and
renamed into place only after success; a pre-existing output is not touched
when source processing fails. `-o -` means standard output. Text is preserved
as UTF-8, with CRLF/LF line endings retained.
