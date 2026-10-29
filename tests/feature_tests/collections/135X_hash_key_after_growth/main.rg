main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    put(.self = $&map, .key = 1, .value = 10, .allocator = allocator)!!!
    iterator ::= to_ro_entry_iterator(.value = &map).iterator
    entry ::= next(.self = $&iterator).value
    index :: Int32 = 2
    while index < 20 {
        put(.self = $&map, .key = index, .value = index, .allocator = allocator)!!!
        index = index + 1
    }
    if entry.key&!= 1 { abort }
    status_code = 0
}
