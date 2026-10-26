test equality_helpers := (.system: System) -> !() {
    testing.expect(.condition = true, .message = "successful checks stay silent")!
    testing.expect_equal(.expected = true, .actual = true)!
    testing.expect_equal(.expected = 1, .actual = 1)!
    testing.expect_equal(.expected = 1.5, .actual = 1.5)!
    testing.expect_equal(.expected = "abc", .actual = "abc")!
    testing.expect_equal_strings(.expected = "", .actual = "")!
    bytes :: [3]UInt8 = (65, 0, 90)
    text_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes     = unwrap_or_abort(.value = slice(&view(&bytes), .start = 0, .count = 3))
            .allocator = system.page_allocator
        )
    )
    text ::= view(&text_storage)
    testing.expect_equal_strings(.expected = text, .actual = text)!
    values :: [3]Int32 = (1, 2, 3)
    testing.expect_equal_views(
        .expected = view(.self = &values), .actual = view(.self = &values)
    )!
    testing.expect_equal_bytes(.expected = view(.self = &bytes), .actual = view(.self = &bytes))!
    empty ::= empty_array_view<.t: UInt8>()
    testing.expect_equal_bytes(.expected = empty, .actual = empty)!
    assume allocator := system.page_allocator
    owner ::= format(.value = "abc", .allocator = allocator)!
    testing.expect_equal_strings(.expected = &owner, .actual = &owner)!
}
