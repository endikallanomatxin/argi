main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    set ::= HashSet#(.key: Int32, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    insert(.self = $&set, .key = 1, .allocator = allocator)!!!
    iterator ::= to_iterator(.value = &set).iterator
    remove(.self = $&set, .key = &1, .allocator = allocator)
    if has_next(.self = &iterator).ok { abort }
    status_code = 0
}
