#### Testing

Testing is a native Argi language feature.

Tests are declared explicitly at top level with the same function-like header shape used by `main`, but prefixed with `test`:

```rg
test my_test(.system: System = System()) -> !() := {
    testing.expect(true)!
}
```

V1 supports exactly this surface shape:

- top-level only
- one input: `.system: System = System()`
- return: `-> !()`

There is no other test syntax in v1.

These are not supported:

- `test "name" { ... }`
- `test name "display name" { ... }`
- name-based conventions such as “functions starting with `test`”

### Discovery and build modes

Tests are discoverable by the compiler and tooling as explicit top-level declarations.

- `argi build` ignores test declarations
- `argi test <module-dir>` discovers and runs tests

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

The official testing helpers live in `core/testing/testing.rg`.

Current helpers:

- `testing.expect(...)`
- `testing.expect_equal(...)`
- `testing.expect_error(...)`
- `testing.fail(...)`
- `testing.skip(...)`

They compose with Argi’s existing `Errable` and `!` flow.

Examples:

```rg
test simple_pass(.system: System = System()) -> !() := {
    testing.expect(true)!
}
```

```rg
test equality(.system: System = System()) -> !() := {
    testing.expect_equal(.expected = 1, .actual = 1)!
}
```

```rg
..some_reason

some_fallible_call() -> (.result: Errable#(.t: Int32, .reasons: (..some_reason))) := {
    result = ..error(.reason = ..some_reason)
}

test expected_error(.system: System = System()) -> !() := {
    call_result := some_fallible_call()
    testing.expect_error(.expected_reason = ..some_reason, .actual_result = call_result)!
}
```

### Failures, skips, and propagated program errors

There is a distinction between testing-framework outcomes and real program errors that happen inside a test.

Testing-framework layer:

- assertion/helper failure -> `..test_failed`
- explicit skip -> `..test_skipped`

Program-under-test layer:

- if test code directly propagates a real error with `!`, that original reason is preserved

So:

- `testing.expect(false)!` fails the test with `..test_failed`
- `testing.skip("not implemented yet")!` skips the test with `..test_skipped`
- `testing.expect_error(...)` fails with `..test_failed` when the actual result succeeds unexpectedly or fails with a different reason
- a direct `some_fallible_call()!` inside a test preserves the original reason from `some_fallible_call`

`testing.expect_error(...)` checks the actual error reason, not merely that an error happened.

### Trace and context

Testing helpers reuse the normal error trace/context machinery.

That means:

- helper-originated failures produce normal traced errors
- `expect_error` mismatch messages appear as normal test failure context
- directly propagated program errors keep their original trace and reasons

### `once`

Because each test is compiled as its own root, `once` is checked independently per test.

This is intentional:

- a `once` function used by test A does not make test B fail
- the semantics remain relative to the selected test entrypoint, not to an artificial combined runner
