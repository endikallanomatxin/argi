main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: String, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    text ::= format(.value = "owned", .allocator = allocator)!!!
    put(.self = $&map, .key = 1, .value = ~text, .allocator = allocator)!!!
    query :: Int32 = 1
    match get_reference(.self = &map, .key = &query).result {
        ..none { abort }
        ..some borrowed {
            text ::= format(.value = "new", .allocator = allocator)!!!
            put(.self = $&map, .key = 1, .value = ~text, .allocator = allocator)!!!
            view(.self = borrowed.value)
        }
    }
    status_code = 0
}
