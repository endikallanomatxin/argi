#### Testing

Testing is a native Argi language feature.

Tests are declared explicitly at top level with the same named-function syntax
used by `main`, prefixed with `test`. The assignment precedes the signature:

```rg
test my_test := () -> !() {
    testing.expect(true)!
}
```

The test entry contract requires:

- top-level only
- optional `.system: System` input supplied by the checked entry wrapper
- ordinary auxiliary inputs, including the required `error_tracer` used by
  testing helpers, resolved from the wrapper's lexical assumptions
- return: `-> !()` for plain errors, or `-> !!()` for traced assertion failures

As with `main` and `#run`, requesting `System` is optional. Input types are
checked through the ordinary generated call, rather than requiring the literal
spelling `System`. Test failure reporting owns its terminal and trace resources
even when the test requests no system input.

These are not supported:

- `test "name" { ... }`
- `test name "display name" { ... }`
- name-based conventions such as “functions starting with `test`”

### Discovery and build modes

Tests are discoverable by the compiler and tooling as explicit top-level declarations.

- `argi build` ignores test declarations
- `argi test <module-dir>` discovers and runs tests without requiring a manifest
- `argi test` runs the current manifest's `[test].modules` list; it does not recursively scan the project

Tests are not semantically merged into one synthetic `main`.
Each test is treated as its own root / entrypoint.

This matters for analyses such as `once`, which are relative to the compiled root. Two different tests are analyzed independently.

### `argi test`

`argi test` builds and runs tests one by one.

Current behavior:

- prints `PASS <name>` for successful tests
- prints `SKIP <name>` for skipped tests
- prints `FAIL <name>` for failing tests
- supports a simple name filter with `--filter`

### `core.testing`

Basic assertions return plain errors and need no tracer or `System`:

- `testing.expect(condition)` checks a Boolean condition.
- `testing.expect_equal(expected, actual)` compares values through equality.
- `testing.expect_error(.expected_reason, .actual_result)` checks a failure's reason.
- `testing.expect_equal_strings`, `expect_equal_views` and `expect_equal_bytes`
  compare text or initialized views.
- `testing.fail()` returns `..test_failed`; `testing.skip()` returns `..test_skipped`.

```rg
test equality := () -> !() {
    testing.expect(true)!
    testing.expect_equal(42, 42)!
}
```

Each helper also has an explicit diagnostic form ending in `_with_trace`.
These forms require `error_tracer`, resolve it through ordinary explicit or
lexically assumed arguments, and return errors carrying its trace. They can
include a message and detailed mismatch information. No default tracer is
provided and no trace is implicitly discarded.

```rg
test detailed_equality := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
    assume error_tracer
    testing.expect_equal_with_trace(42, 42, .message = "vertex count")!
}
```

Both forms preserve the same assertion failure and skip reasons. A plain test
uses `!` to propagate ordinary failures. A traced test promotes those failures
explicitly with `!! "context"`; forwarding an existing trace with `!` adds no
context. Prefer a context describing the test's intent over repeating each
operation's name. Tests that inspect error traces use the diagnostic forms.

`expect_error` examines the actual reason, not merely whether an error occurred.
Its result is a normal assertion error even when the inspected result was traced;
it consumes that result explicitly instead of converting or propagating its error.
Unexpected successful owning values receive ordinary lexical cleanup.

### `once`

Because each test is compiled as its own root, `once` is checked independently per test.

This is intentional:

- a `once` function used by test A does not make test B fail
- the semantics remain relative to the selected test entrypoint, not to an artificial combined runner

> [!IDEA] Compiler tests through the API
> Run compiler regression fixtures through the compiler API with fresh mutable
> state per fixture, keeping a small CLI test layer. Avoiding a CLI invocation
> per fixture need not mean running every test program in the runner's process:
> worker processes could isolate crashes and let timeouts stop hung tests.
> This could reuse REPL and comptime session infrastructure while keeping each
> fixture's mutable state independent.

> [!IDEA] Test autodiscovery
> Explore automatic discovery of tests into a tree following the module
> hierarchy, so tooling can list, select and run individual tests or subtrees.
> Define the discovery scope, including whether imported dependencies contribute
> tests, while preserving each test's independent root semantics.

### Equality diagnostics

`expect_with_trace` and `expect_equal_with_trace` accept a bounded `.message: StringView`
that supplies caller context. Integer, floating-point, and Boolean equality
failures report the expected and actual values; other comparable types retain
an ordinary equality failure message. Successful checks produce no output.

`expect_equal_strings_with_trace(.expected, .actual, .message)` compares complete byte
extents, including embedded NULs. Inputs may be two StringViews or two borrowed
Strings. `expect_equal_with_trace` also compares StringViews by their byte contents.
Failures report the first differing byte index, expected and actual byte values
(or `<end>` for a shorter input), and both lengths. Indices count bytes, not
Unicode scalars or graphemes.

`expect_equal_views_with_trace(.expected, .actual, .message)` compares readonly initialized
array views element by element. Element types must support equality. Failures
report the first differing element index and both lengths. A differing length
reports the common-prefix length as its index. `expect_equal_bytes_with_trace` additionally
reports byte values or `<end>`. Empty views require no data pointer.

Assertion diagnostics use bounded stack storage and require no allocator.
Each diagnostic context is limited to 128 bytes; the bounded error tracer
reports truncation when caller context exceeds its capacity. Test failures and
skips print their captured error trace before entry resources are cleaned up.
The original reason still determines failure or skip status. Tracer buffers and
borrowed context storage do not escape the test entry scope.
