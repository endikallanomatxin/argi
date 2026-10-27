main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    put(.self = $&map, .key = 1, .value = 10, .allocator = allocator)!!!
    iterator ::= to_iterator(.value = &map).iterator
    put(.self = $&map, .key = 1, .value = 20, .allocator = allocator)!!!
    if has_next(.self = &iterator).ok { abort }
    status_code = 0
}
