test string_mismatch(.system: System) -> !() := {
    testing.expect_equal_strings(.expected = "abc", .actual = "axc", .message = "checking payload")!
}

test string_prefix(.system: System) -> !() := {
    testing.expect_equal_strings(.expected = "abc", .actual = "ab")!
}

test string_empty(.system: System) -> !() := {
    testing.expect_equal_strings(.expected = "", .actual = "x")!
}

test string_embedded_nul(.system: System) -> !() := {
    expected :: [3]UInt8 = (65, 0, 90)
    actual :: [3]UInt8 = (65, 0, 91)
    testing.expect_equal_strings(
        .expected = StringView(.data = &expected[0], .length = 3)
        .actual   = StringView(.data = &actual[0], .length = 3)
    )!
}
