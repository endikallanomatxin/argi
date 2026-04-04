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
    result = ..ok(.value = Void())
}

skip(.message: &Char) -> (.result: Errable#(.t: Void, .reasons: (..test_skipped))) := {
    test_skip_impl() !! message
    result = ..ok(.value = Void())
}

expect(.condition: Bool) -> (.result: Errable#(.t: Void, .reasons: (..test_failed))) := {
    if condition {
        result = ..ok(.value = Void())
        return
    }

    fail(.message = "expect failed: condition was false")!
}

expect_equal #(.t: Type) (
    .expected: t,
    .actual: t,
) -> (.result: Errable#(.t: Void, .reasons: (..test_failed))) := {
    if expected == actual {
        result = ..ok(.value = Void())
        return
    }

    fail(.message = "expect_equal failed: expected and actual differ")!
}
