main(.system: System) -> () := {
    assume allocator := system.page_allocator
    text ::= unwrap_or_abort(.value = string_from_bytes(.bytes = string_bytes(.text = "abc")))
    scalars ::= codepoints(.text = as_view(&text))
    unwrap_or_abort(.value = set_ascii($&text, .index = 0, .byte = 65))
    _ ::= length(&scalars)
}
