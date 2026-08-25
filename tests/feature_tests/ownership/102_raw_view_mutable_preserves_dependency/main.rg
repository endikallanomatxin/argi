preserve_data(.self: $&StringView) -> () := {
    self&.data = self&.data
}

main(.system: System = System()) -> (.status_code: Int32) := {
    text ::= String(.capacity = 1)
    push_byte(.self = $&text, .byte = 42, .allocator = system.allocator)
    view ::= as_view(.self = &text)
    preserve_data(.self = $&view)
    byte ::= bytes_get(.view = &view, .index = 0).byte
    deinit(.self = $&text, .allocator = system.allocator)
    if byte == 42 {
        status_code = 0
    } else {
        status_code = 1
    }
}
