..test_failed
..test_skipped

test_fail_impl() -> (.result: Errable#(.t: Void, .reasons: (..test_failed))) := {
    result = ..error(.reason = ..test_failed)
}

test_skip_impl() -> (.result: Errable#(.t: Void, .reasons: (..test_skipped))) := {
    result = ..error(.reason = ..test_skipped)
}

fail(.message: &Char) -> (.result: Errable#(.t: Void, .reasons: (..test_failed))) := {
    test_fail_impl() !! message
    result = ..ok Void()
}

skip(.message: &Char) -> (.result: Errable#(.t: Void, .reasons: (..test_skipped))) := {
    test_skip_impl() !! message
    result = ..ok Void()
}

expect(.condition: Bool) -> (.result: Errable#(.t: Void, .reasons: (..test_failed))) := {
    if condition {
        result = ..ok Void()
        return
    }

    fail(.message = "expect failed: condition was false")!
}

expect_equal #(.t: Type) (
    .expected: t,
    .actual: t,
) -> (.result: Errable#(.t: Void, .reasons: (..test_failed))) := {
    if expected == actual {
        result = ..ok Void()
        return
    }

    fail(.message = "expect_equal failed: expected and actual differ")!
}

expect_error #(.t: Type, .reasons: Type) (
    .expected_reason: reasons,
    .actual_result: Errable#(.t: t, .reasons: reasons),
) -> (.result: Errable#(.t: Void, .reasons: (..test_failed))) := {
    fail(.message = "testing.expect_error must be lowered by the compiler")!
}
