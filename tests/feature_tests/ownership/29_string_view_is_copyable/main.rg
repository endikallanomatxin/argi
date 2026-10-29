measure := (.view: StringView) -> (.count: UIntNative) {
    count = byte_length(&view).count
}

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    text ::= unwrap_or_abort(.value = String(.length = 4))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 65))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 114))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 2, .byte = 103))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 3, .byte = 105))

    first_view ::= view(.self = &text)
    second_view: StringView = first_view

    if measure(.view = second_view).count != 4 {
        status_code = 1
        deinit(.self = $&text)
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
