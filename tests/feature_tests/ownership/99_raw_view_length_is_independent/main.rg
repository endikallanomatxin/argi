main(.system: System = System()) -> (.status_code: Int32) := {
    text ::= String(.capacity = 4)
    push_byte(.self = $$&text, .byte = 42, .allocator = system.allocator)
    view ::= as_view(.self = &text)

    deinit(.self = $$&text, .allocator = system.allocator)
    if view.length == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
}
