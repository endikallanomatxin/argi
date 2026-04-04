test equality(.system: System = System()) -> !() := {
    testing.expect_equal(.expected = 1, .actual = 1)!
}
