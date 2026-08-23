replace_data(.self: $&StringView, .next: StringView) -> () := {
    self&.data = next.data
}

main(.system: System = System()) -> (.status_code: Int32) := {
    first ::= String(.capacity = 1)
    second ::= String(.capacity = 1)
    view ::= as_view(.self = &first)
    next ::= as_view(.self = &second)

    replace_data(.self = $&view, .next = next)
    deinit(.self = $$&first, .allocator = system.allocator)
    deinit(.self = $$&second, .allocator = system.allocator)
    status_code = 0
}
