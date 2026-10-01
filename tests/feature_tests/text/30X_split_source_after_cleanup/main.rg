main(.system: System) -> (.status_code: Int32 = 0) := {
    text ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 1))
    bytes_set(.string = $&text, .index = 0, .value = 97)
    iterator ::= unwrap_or_abort(.value = split(.self = as_view(.self = &text).view, .separator = ","))
    deinit(.self = $&text, .allocator = system.page_allocator)
    segment ::= next(.self = $&iterator).value
    if segment == "a" { abort }
}
