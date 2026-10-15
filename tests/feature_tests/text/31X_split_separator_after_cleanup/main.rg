main(.system: System) -> (.status_code: Int32 = 0) := {
    separator ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 1))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&separator, .index = 0, .byte = 44))
    iterator ::= unwrap_or_abort(
        .value = split(.self = "a,b", .separator = as_view(.self = &separator).view)
    )
    deinit(.self = $&separator)
    segment ::= next(.self = $&iterator).value
    if segment == "a" { abort }
}
