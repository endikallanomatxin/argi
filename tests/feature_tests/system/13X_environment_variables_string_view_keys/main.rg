main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    home_string ::= unwrap_or_abort(.value = String(.length = 4))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&home_string, .index = 0, .byte = 72))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&home_string, .index = 1, .byte = 79))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&home_string, .index = 2, .byte = 77))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&home_string, .index = 3, .byte = 69))

    home_view ::= view(.self = &home_string)

    has_result ::= has(.self = system.env_vars, .key = home_view)
    if is(.value = has_result, .variant = ..ok) and has_result ..ok {
    } else {
        status_code = 1
        return
    }

    from_view_result ::= system.env_vars[home_view]
    if is(.value = from_view_result, .variant = ..error) {
        status_code = 3
        return
    }
    from_view ::= from_view_result ..ok
    if is(.value = from_view, .variant = ..some) {
    } else {
        status_code = 2
        return
    }

    deinit(.self = $&home_string)
    status_code = 0
}
