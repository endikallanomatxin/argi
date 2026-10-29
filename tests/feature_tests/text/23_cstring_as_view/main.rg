main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    c_text ::= from_literal(.data = "hello")
    assume allocator ::= system.page_allocator
    text ::= unwrap_or_abort(.value = string_from_c_string(.text = c_text))
    view ::= view(&text)

    if byte_length(&view).count != 5 {
        status_code = 1
        return
    }

    if unwrap_or_abort(.value = bytes_get(.view = &view, .index = 0)) != 104 {
        status_code = 2
        return
    }

    if unwrap_or_abort(.value = bytes_get(.view = &view, .index = 4)) != 111 {
        status_code = 3
        return
    }

    status_code = 0
}
