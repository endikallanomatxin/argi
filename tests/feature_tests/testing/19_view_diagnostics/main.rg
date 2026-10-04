test view_mismatch(.system: System) -> !() := {
    expected :: [3]Int32 = (1, 2, 3)
    actual :: [3]Int32 = (1, 9, 3)
    testing.expect_equal_views(
        .expected = view(.array = &expected)
        .actual   = view(.array = &actual)
    )!
}

test byte_prefix(.system: System) -> !() := {
    expected :: [2]UInt8 = (1, 2)
    actual :: [1]UInt8 = (1)
    testing.expect_equal_bytes(
        .expected = view(.array = &expected)
        .actual   = view(.array = &actual)
    )!
}
