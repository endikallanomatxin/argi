# Semantic versions

The explicit `semver` module implements the syntax and precedence of
[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

```rg
semver := import("semver")
main() -> (.status_code: Int32 = 0) := {
    first ::= unwrap_or_abort(.value = semver.VersionView(.text = "1.2.3-rc.1")).result
    second ::= unwrap_or_abort(.value = semver.parse(.text = "1.2.3+build.001")).result
    if semver.compare(.left = &first, .right = &second).order >= 0 { abort }
}
```

`parse(.text: StringView)` and `VersionView(.text: StringView)` return
`Errable<VersionView, invalid_input>`. Parsing consumes the entire input and
requires three decimal components without leading zeroes, optional prerelease
identifiers after `-`, and optional build identifiers after `+`. Identifiers
are nonempty dot-separated ASCII letters, digits, or hyphens. Numeric
prerelease identifiers cannot have leading zeroes; build identifiers can.
Whitespace, a `v` prefix, abbreviated versions, non-ASCII text, embedded NUL,
and version-range expressions are rejected.

`VersionView` is an implicitly copyable borrowed value. Parsing and comparison
need no allocator, FFI, or system capability. Numeric components and identifiers
have no fixed integer limit: their text is compared by digit count and then
ASCII digits. Only the source view's native length bounds their size. Private
validated state prevents external modules from forging component boundaries.
The source bytes must stay alive and unchanged while the version is used.

`as_view(.self: &VersionView)` returns the full `.text: StringView`.
`major`, `minor`, `patch`, `pre_release`, and `build_metadata` return component
text without separators. Missing prerelease or build metadata is an empty view.
These accessors preserve borrowing; they do not allocate or parse again.

`compare(.left: &VersionView, .right: &VersionView)` returns `.order: Int32`
with exactly -1, 0, or 1. It compares the three numeric components, then
prerelease identifiers: numeric identifiers precede nonnumeric identifiers,
nonnumeric text uses ASCII order, and a shared prefix precedes a longer sequence.
A release follows prereleases with the same three numeric components.
Build metadata does not affect precedence. `same_precedence` reports whether
`compare` returns zero. `equals` and `==`/`!=` compare the complete validated
text, including build metadata; equal precedence does not imply exact equality.

`format(.value: &VersionView, .allocator: $&Allocator)` returns an owning
`String` in `Errable<String, out_of_memory>`. It copies the exact validated
spelling, including metadata. `format_into(.out: $&String, .value: &VersionView,
.allocator: $&Allocator)` appends that spelling and returns
`Errable<Void, out_of_memory>`; reserved capacity avoids further allocation.
`format_into(.out: $&Writer, .value: &VersionView)` writes it without allocation
and returns the existing `stream_write_failed` or `stream_flush_failed` errors.
It does not flush or add a newline. As with ordinary string append, the source
view must not borrow a destination buffer whose growth could invalidate it.

Version range selection, package resolution, and compatibility policies are
separate from this strict version-value module.
