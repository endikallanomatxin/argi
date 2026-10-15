main(.system: System) -> (.status_code: Int32) := {
    assume ffi := system.ffi
    c_text ::= from_literal(.data = "hello")
    assume allocator ::= system.page_allocator
    text ::= unwrap_or_abort(.value = string_from_c_string(.text = c_text))
    view ::= as_view(&text)

    if byte_length(&view).count != 5 {
        status_code = 1
        return
    }

    if bytes_get(.view = &view, .index = 0).byte != 104 {
        status_code = 2
        return
    }

    if bytes_get(.view = &view, .index = 4).byte != 111 {
        status_code = 3
        return
    }

    status_code = 0
}
