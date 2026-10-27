main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    text ::= format(.value = "hello", .allocator = allocator)!!!
    validated ::= CodepointView(.text = view(.self = &text))
    iterator ::= to_iterator(.value = &validated).iterator
    deinit(.self = $&text)
    next(.self = $&iterator)
    status_code = 0
}
