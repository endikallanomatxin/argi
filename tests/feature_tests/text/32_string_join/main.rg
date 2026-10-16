main(.system: System) -> (.status_code: Int32 = 0) := {
    parts: [3]StringView = ("a", "", "b")
    joined ::= unwrap_or_abort(
        .value = join(
            .parts = view(.self = &parts), .separator = "--", .allocator = system.page_allocator
        )
    )
    if view(.self = &joined).view != "a----b" { abort }
    deinit(.self = $&joined)
    joined_empty_separator ::= unwrap_or_abort(
        .value = join(
            .parts = view(.self = &parts), .separator = "", .allocator = system.page_allocator
        )
    )
    if view(.self = &joined_empty_separator).view != "ab" { abort }
    deinit(.self = $&joined_empty_separator)
    empty_parts: [0]StringView = ()
    empty ::= unwrap_or_abort(
        .value = join(
            .parts     = view(.self = &empty_parts)
            .separator = ","
            .allocator = system.page_allocator
        )
    )
    if byte_length(&empty).count != 0 { abort }
    deinit(.self = $&empty)
    source ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&source, .index = 0, .byte = 97))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&source, .index = 1, .byte = 0))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&source, .index = 2, .byte = 98))
    borrowed_view ::= view(.self = &source).view
    aliased: [2]StringView = (borrowed_view, borrowed_view)
    independent ::= unwrap_or_abort(
        .value = join(
            .parts     = view(.self = &aliased)
            .separator = borrowed_view
            .allocator = system.page_allocator
        )
    )
    deinit(.self = $&source)
    if byte_length(&independent).count != 9 { abort }
    if unwrap_or_abort(.value = bytes_get(.view = &independent, .index = 7)) != 0 { abort }
    if unwrap_or_abort(.value = bytes_get(.view = &independent, .index = 8)) != 98 { abort }
    deinit(.self = $&independent)
}
