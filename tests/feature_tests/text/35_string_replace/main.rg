expect_replacement := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .text         : StringView,
    .pattern      : StringView,
    .replacement  : StringView,
    .expected     : StringView,
    .allocator    : $&AllocatorType,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> () {
    assume error_tracer
    output ::= unwrap_or_abort(
        .value = replace(
            .self = text, .pattern = pattern, .replacement = replacement, .allocator = allocator
        )
    )
    if equals(.left = view(.self = &output).view, .right = expected).ok == false { abort }
    if [
        is(
            .value   = bytes_get(.view = &output, .index = byte_length(&output).count)
            .variant = ..error
        )
        == false
    ] { abort }
    deinit(.self = $&output)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    expect_replacement(
        .text        = ""
        .pattern     = "a"
        .replacement = "b"
        .expected    = ""
        .allocator   = system.page_allocator
    )
    expect_replacement(
        .text        = "abc"
        .pattern     = "z"
        .replacement = "x"
        .expected    = "abc"
        .allocator   = system.page_allocator
    )
    expect_replacement(
        .text        = "abc"
        .pattern     = "abcd"
        .replacement = "x"
        .expected    = "abc"
        .allocator   = system.page_allocator
    )
    expect_replacement(
        .text        = "aaa"
        .pattern     = "aa"
        .replacement = "x"
        .expected    = "xa"
        .allocator   = system.page_allocator
    )
    expect_replacement(
        .text        = "aaaa"
        .pattern     = "aa"
        .replacement = "x"
        .expected    = "xx"
        .allocator   = system.page_allocator
    )
    expect_replacement(
        .text        = "--a----"
        .pattern     = "--"
        .replacement = "!"
        .expected    = "!a!!"
        .allocator   = system.page_allocator
    )
    expect_replacement(
        .text        = "banana"
        .pattern     = "na"
        .replacement = ""
        .expected    = "ba"
        .allocator   = system.page_allocator
    )
    expect_replacement(
        .text        = "aaa"
        .pattern     = "a"
        .replacement = "aa"
        .expected    = "aaaaaa"
        .allocator   = system.page_allocator
    )
    source ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&source, .index = 0, .byte = 97))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&source, .index = 1, .byte = 0))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&source, .index = 2, .byte = 98))
    view ::= view(.self = &source).view
    -- All three descriptors borrow the same storage. The replacement bytes
    -- are copied once per original match, never searched recursively.
    independent ::= unwrap_or_abort(
        .value = replace(
            .self        = view
            .pattern     = view
            .replacement = view
            .allocator   = system.page_allocator
        )
    )
    deinit(.self = $&source)
    if byte_length(&independent).count != 3 { abort }
    if unwrap_or_abort(.value = bytes_get(.view = &independent, .index = 1)) != 0 { abort }
    deinit(.self = $&independent)
    binary: [3]UInt8 = (97, 0, 98)
    binary_view: StringView = "a\0b"
    zero: StringView = "\0"
    expect_replacement(
        .text        = binary_view
        .pattern     = zero
        .replacement = "--"
        .expected    = "a--b"
        .allocator   = system.page_allocator
    )
}
