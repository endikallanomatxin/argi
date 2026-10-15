main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    text ::= unwrap_or_abort(.value = String(.length = 3))

    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 65))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 114))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 2, .byte = 103))

    first ::= bytes_get(.view = &text, .index = 0).byte
    second ::= bytes_get(.view = &text, .index = 1).byte
    third ::= bytes_get(.view = &text, .index = 2).byte

    if first != 65 {
        status_code = 1
        return
    }

    if second != 114 {
        status_code = 2
        return
    }

    if third != 103 {
        status_code = 3
        return
    }

    status_code = 0
}
