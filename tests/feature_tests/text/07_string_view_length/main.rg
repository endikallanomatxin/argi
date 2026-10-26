main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    text ::= unwrap_or_abort(.value = String(.length = 2))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 79))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 75))

    view ::= view(.self = &text)
    if byte_length(&view).count != 2 {
        status_code = 1
        return
    }

    if unwrap_or_abort(.value = bytes_get(.view = &view, .index = 0)) != 79 {
        status_code = 2
        return
    }

    if unwrap_or_abort(.value = bytes_get(.view = &view, .index = 1)) != 75 {
        status_code = 3
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
