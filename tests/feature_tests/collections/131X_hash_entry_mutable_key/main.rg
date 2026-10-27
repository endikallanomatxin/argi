main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    put(.self = $&map, .key = 1, .value = 10, .allocator = allocator)!!!
    iterator ::= to_rw_entry_iterator(.value = $&map).iterator
    entry ::= next(.self = $&iterator).value
    entry.key&= 2
    status_code = 0
}
