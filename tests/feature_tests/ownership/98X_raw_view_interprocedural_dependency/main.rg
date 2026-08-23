identity(.view: StringView) -> (.out: StringView) := {
    out = view
}

main(.system: System = System()) -> (.status_code: Int32) := {
    text ::= String(.capacity = 4)
    view ::= as_view(.self = &text)
    returned ::= identity(.view = view)

    deinit(.self = $$&text, .allocator = system.allocator)
    byte ::= bytes_get(.view = &returned, .index = 0).byte
    if byte == 0 {
        status_code = 0
    } else {
        status_code = 1
    }
}
