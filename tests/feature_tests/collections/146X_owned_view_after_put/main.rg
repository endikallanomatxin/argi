main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: String, .value: UIntNative, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    key ::= format(.value = "key", .allocator = allocator)!!!
    put(.self = $&map, .key = ~key, .value = 1, .allocator = allocator)!!!
    match get_mutable_reference(.self = $&map, .key = "key").result {
        ..none { abort }
        ..some borrowed {
            other ::= format(.value = "other", .allocator = allocator)!!!
            put(.self = $&map, .key = ~other, .value = 2, .allocator = allocator)!!!
            if borrowed.value&== 1 { abort }
        }
    }
    status_code = 0
}
