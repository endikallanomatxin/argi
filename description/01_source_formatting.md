# Source formatting

The standard formatter uses four spaces for indentation and a soft width of
100 columns. Parentheses, brackets, and braces determine indentation; existing
line breaks in calls, lists, and blocks are retained. Long comma-separated
expressions can acquire additional breaks. Lines without a safe break point,
including comments and strings, may exceed the width.

Opening braces remain on the same line as their declaration or condition.
Small single-line bodies remain single-line, and empty bodies use `{}`.
Multiline bodies remain multiline; formatting does not add implicit returns.

Consecutive fields in multiline structs align their names, type markers,
types, and default-value assignments. This applies equally to the structural
input and value literals used by calls. Comments and blank lines separate
alignment groups. Other declarations use uniform spacing.

Comments, literal contents, declaration order, import order, and field order
are preserved. Blank-line runs become at most one blank line, leading and
trailing blank lines are removed, and nonempty files end with a newline.
Formatting is idempotent.

`argi fmt` accepts `.rg` files and directories, defaulting to the current
directory. Directories are searched recursively, excluding hidden entries,
`zig-out`, `references`, and `node_modules`. `--check` reports files requiring
formatting and exits unsuccessfully without changing them. `--stdout` accepts
one `.rg` file and prints its formatted contents. The two flags are mutually
exclusive. Edits are prepared before files are written; files with damaged
tokens or delimiters are left untouched. The LSP uses the same formatter on
the editor's current document, including unsaved changes.
