# Source formatting

The standard formatter uses four spaces for indentation and a soft width of
100 columns. Parentheses, brackets, and braces determine indentation; existing
line breaks in calls, lists, and blocks are retained. A multiline collection
places its opening and closing delimiters on separate lines and uses one row
per field. Long calls expand their complete argument group rather than moving
only the final argument to a continuation line. Lines without a safe break point,
including comments and strings, may exceed the width.

Opening braces remain on the same line as their declaration or condition.
A short body containing one statement can remain on one line; a body with
multiple statements expands, including loops and conditional bodies. Empty
bodies use `{}`. Multiline bodies remain multiline; formatting does not add
implicit returns. Functions and global type declarations have at least one
blank line between declarations, with leading documentation comments kept
attached to their declaration.

Function signatures have inline and multiline layouts. A signature that fits
on one line stays inline. Long signatures expand their nonempty comptime,
input, and output groups together; a manually multiline group also selects
that layout. Signature fields use eight spaces and closing delimiters use
four spaces, while the function body uses ordinary four-space indentation:

```rg
add#(
        .n : UIntNative
        .t : Type: Scalar
    )(
        .left  : &Vector#(.n = n, .t: t)
        .right : &Vector#(.n = n, .t: t)
    ) -> (
        .result : Vector#(.n = n, .t: t)
    ) := {
    result = left&
}
```

Existing commas are preserved. Nested type arguments that fit on one line can
stay compact inside a multiline signature.

Consecutive fields in multiline structs align their names, type markers,
types, and default-value assignments. This applies equally to the structural
input and value literals used by calls. Comments and blank lines separate
alignment groups. Other declarations use uniform spacing.

Comments, literal contents, declaration order, import order, and field order
are preserved. Blank-line runs become at most one blank line, leading and
trailing blank lines are removed, and nonempty files end with a newline.
Formatting is idempotent. Edits preserve token contents and, for a syntactically
valid document, the syntax structure before they are returned or written.

`argi format` accepts `.rg` files and directories, defaulting to the current
directory. Directories are searched recursively, excluding hidden entries,
`zig-out`, `references`, and `node_modules`. `--check` reports files requiring
formatting and exits unsuccessfully without changing them. `--stdout` accepts
one `.rg` file and prints its formatted contents. The two flags are mutually
exclusive. Edits are prepared before files are written; files with damaged
tokens or delimiters are left untouched. The LSP uses the same formatter on
the editor's current document, including unsaved changes.
