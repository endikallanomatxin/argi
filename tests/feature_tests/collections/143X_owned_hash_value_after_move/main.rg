main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap<.key: Int32, .value: String, .policy: StandardHashPolicy>(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    text ::= format(.value = "owned", .allocator = allocator)!!!
    put(.self = $&map, .key = 1, .value = ~text, .allocator = allocator)!!!
    query :: Int32 = 1
    view(.self = &text)
    status_code = 0
}
