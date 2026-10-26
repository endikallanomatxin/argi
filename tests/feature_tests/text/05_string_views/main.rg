main := (.system: System) -> (.status_code: Int32) {
    assume ffi := system.ffi
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    text ::= unwrap_or_abort(.value = String(.length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 65))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 114))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 2, .byte = 103))

    nul_rejected ::= is(.value = bytes_get(.view = &text, .index = 3), .variant = ..error)
    if nul_rejected == false {
        status_code = 1
        return
    }

    view ::= view(.self = &text)
    if unwrap_or_abort(.value = bytes_get(.view = &view, .index = 0)) != 65 {
        status_code = 2
        return
    }

    c_text ::= as_c_string(.self = &text)
    if strlen(.string = c_text).length != 3 {
        status_code = 3
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
