forward := (.text: StringView) -> (.view: StringView) {
    view = trim(.self = text).view
}

main := (.system: System) -> (.status_code: Int32 = 0) {

    text ::= unwrap_or_abort(.value = String(.allocator = system.page_allocator, .length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 32))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 97))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 2, .byte = 32))
    view ::= forward(.text = view(.self = &text).view).view
    deinit(.self = $&text)
    if contains(.self = view, .pattern = "a").ok { abort }
}
