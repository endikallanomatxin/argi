main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: String, .value: String, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    key ::= format(.value = "key", .allocator = allocator)!!!
    value ::= format(.value = "first", .allocator = allocator)!!!
    put(.self = $&map, .key = ~key, .value = ~value, .allocator = allocator)!!!
    query ::= format(.value = "key", .allocator = allocator)!!!
    match get_reference(.self = &map, .key = view(&query)).result {
        ..none { abort }
        ..some borrowed {
            if [equals(.left = view(.self = borrowed.value), .right = "first").ok == false] {
                abort
            }
        }
    }
    replacement_key ::= format(.value = "key", .allocator = allocator)!!!
    replacement_value ::= format(.value = "second", .allocator = allocator)!!!
    put(
        .self      = $&map
        .key       = ~replacement_key
        .value     = ~replacement_value
        .allocator = allocator
    )!!!
    if length(.self = &map).count != 1 { abort }
    extracted ::= extract(.self = $&map, .key = view(&query)).result
    if length(.self = &map).count != 0 { abort }
    deinit(.self = $&map)
    match extracted {
        ..none { abort }
        ..some ~payload {
            entry ::= ~payload.value
            if equals(.left = view(.self = &entry.key), .right = "key").ok == false {
                abort
            }
            if equals(.left = view(.self = &entry.value), .right = "second").ok == false {
                abort
            }
        }
    }
    status_code = 0
}
