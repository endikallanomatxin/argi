increment_and_is_true(.value: $&Int32) -> (.ok: Bool) := {
    value& = value& + 1
    ok = true
}

test language_regression_slice(.system: System = System()) -> !() := {
    present : ?Int32 = ..some(.value = 5)
    missing : ?Int32 = ..none
    left ::= present unwrap_or 1
    right ::= missing unwrap_or 7
    testing.expect_equal(.expected = 12, .actual = left + right)!

    side_effect :: Int32 = 0
    if true or increment_and_is_true(.value = $&side_effect) {
    }
    testing.expect_equal(.expected = 0, .actual = side_effect)!

    if false and increment_and_is_true(.value = $&side_effect) {
    }
    testing.expect_equal(.expected = 0, .actual = side_effect)!

    if false or increment_and_is_true(.value = $&side_effect) {
    }
    testing.expect_equal(.expected = 1, .actual = side_effect)!
}
