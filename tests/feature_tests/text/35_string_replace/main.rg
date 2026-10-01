expect_replacement(.text: StringView, .pattern: StringView, .replacement: StringView, .expected: StringView, .allocator: $&Allocator) -> () := {
    output ::= unwrap_or_abort(.value = replace(.self = text, .pattern = pattern, .replacement = replacement, .allocator = allocator))
    if equals(.left = as_view(.self = &output).view, .right = expected).ok == false { abort }
    if bytes_get(.string = &output, .index = output.length).byte != 0 { abort }
    deinit(.self = $&output, .allocator = allocator)
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    expect_replacement(.text = "", .pattern = "a", .replacement = "b", .expected = "", .allocator = system.page_allocator)
    expect_replacement(.text = "abc", .pattern = "z", .replacement = "x", .expected = "abc", .allocator = system.page_allocator)
    expect_replacement(.text = "abc", .pattern = "abcd", .replacement = "x", .expected = "abc", .allocator = system.page_allocator)
    expect_replacement(.text = "aaa", .pattern = "aa", .replacement = "x", .expected = "xa", .allocator = system.page_allocator)
    expect_replacement(.text = "aaaa", .pattern = "aa", .replacement = "x", .expected = "xx", .allocator = system.page_allocator)
    expect_replacement(.text = "--a----", .pattern = "--", .replacement = "!", .expected = "!a!!", .allocator = system.page_allocator)
    expect_replacement(.text = "banana", .pattern = "na", .replacement = "", .expected = "ba", .allocator = system.page_allocator)
    expect_replacement(.text = "aaa", .pattern = "a", .replacement = "aa", .expected = "aaaaaa", .allocator = system.page_allocator)
    source ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    bytes_set(.string = $&source, .index = 0, .value = 97)
    bytes_set(.string = $&source, .index = 1, .value = 0)
    bytes_set(.string = $&source, .index = 2, .value = 98)
    view ::= as_view(.self = &source).view
    -- All three descriptors borrow the same storage. The replacement bytes
    -- are copied once per original match, never searched recursively.
    independent ::= unwrap_or_abort(.value = replace(.self = view, .pattern = view, .replacement = view, .allocator = system.page_allocator))
    deinit(.self = $&source, .allocator = system.page_allocator)
    if independent.length != 3 { abort }
    if bytes_get(.string = &independent, .index = 1).byte != 0 { abort }
    deinit(.self = $&independent, .allocator = system.page_allocator)
    binary : [3]UInt8 = (97, 0, 98)
    binary_view :: StringView = (.data = &binary[0], .length = 3)
    zero :: StringView = (.data = &binary[1], .length = 1)
    expect_replacement(.text = binary_view, .pattern = zero, .replacement = "--", .expected = "a--b", .allocator = system.page_allocator)
}
