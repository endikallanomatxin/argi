test signed_value(.system: System) -> !() := {
    expected :: Int64 = -9223372036854775808
    actual :: Int64 = 9223372036854775807
    testing.expect_equal(
        .expected = expected
        .actual   = actual
        .message  = "checking signed bounds"
    )!
}

test unsigned_value(.system: System) -> !() := {
    expected :: UInt64 = 18446744073709551615
    actual :: UInt64 = 0
    testing.expect_equal(.expected = expected, .actual = actual)!
}

test float_value(.system: System) -> !() := {
    testing.expect_equal(.expected = 1.5, .actual = 2.5)!
}

test bool_value(.system: System) -> !() := {
    testing.expect_equal(.expected = true, .actual = false)!
}
