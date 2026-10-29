main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    text ::= unwrap_or_abort(.value = String(.length = 0))

    if byte_length(&text).count != 0 {
        status_code = 1
        return
    }

    nul_rejected ::= is(.value = bytes_get(.view = &text, .index = 0), .variant = ..error)
    if nul_rejected == false {
        status_code = 2
        return
    }

    c_text ::= as_c_string(.self = &text)
    if strlen(.string = c_text).length != 0 {
        status_code = 3
        return
    }

    deinit(.self = $&text)
    status_code = 0
}
