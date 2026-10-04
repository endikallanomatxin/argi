test equality_helpers(.system: System) -> !() := {
    testing.expect(.condition = true, .message = "successful checks stay silent")!
    testing.expect_equal(.expected = true, .actual = true)!
    testing.expect_equal(.expected = 1, .actual = 1)!
    testing.expect_equal(.expected = 1.5, .actual = 1.5)!
    testing.expect_equal(.expected = "abc", .actual = "abc")!
    testing.expect_equal_strings(.expected = "", .actual = "")!
    bytes :: [3]UInt8 = (65, 0, 90)
    text :: StringView = (.data = &bytes[0], .length = 3)
    testing.expect_equal_strings(.expected = text, .actual = text)!
    values :: [3]Int32 = (1, 2, 3)
    testing.expect_equal_views(
        .expected = view(.array = &values)
        .actual   = view(.array = &values)
    )!
    testing.expect_equal_bytes(.expected = view(.array = &bytes), .actual = view(.array = &bytes))!
    empty ::= array_view_ro#(.t: UInt8)()
    testing.expect_equal_bytes(.expected = empty, .actual = empty)!
    assume allocator := system.page_allocator
    owner ::= format(.value = "abc", .allocator = allocator)!
    testing.expect_equal_strings(.expected = &owner, .actual = &owner)!
}
