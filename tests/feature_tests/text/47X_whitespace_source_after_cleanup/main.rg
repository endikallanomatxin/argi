main(.system: System) -> (.status_code: Int32 = 0) := {
    text ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 1))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 97))
    iterator ::= split_whitespace(.self = view(.self = &text).view)
    deinit(.self = $&text)
    segment ::= next(.self = $&iterator).value
    if segment == "a" { abort }
}
