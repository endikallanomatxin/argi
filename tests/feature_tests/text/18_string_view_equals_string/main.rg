main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    text :: String = unwrap_or_abort(
        .value = String(.allocator = $&allocator_storage, .length = 5)
    )
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 104))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 101))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 2, .byte = 108))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 3, .byte = 108))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 4, .byte = 111))

    text_view ::= view(.self = &text)
    text_view_again ::= view(.self = &text)
    if text_view == text_view_again {
        status_code = 0
    } else {
        status_code = 1
    }
}
