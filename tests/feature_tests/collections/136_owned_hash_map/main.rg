main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= OwnedHashMap#(.key: String, .value: String, .policy: StringHashPolicy)(
        .policy    = StringHashPolicy()
        .allocator = allocator
    )!
    key ::= format(.value = "key", .allocator = allocator)!
    value ::= format(.value = "first", .allocator = allocator)!
    put(.self = $&map, .key = ~key, .value = ~value, .allocator = allocator)!
    query ::= format(.value = "key", .allocator = allocator)!
    match get_ro_ref(.self = &map, .key = &query).result {
        ..none { abort }
        ..some borrowed {
            if [
                equals(.left = as_view(.self = borrowed.value), .right = "first").ok
                == false
            ] { abort }
        }
    }
    replacement_key ::= format(.value = "key", .allocator = allocator)!
    replacement_value ::= format(.value = "second", .allocator = allocator)!
    put(
        .self      = $&map
        .key       = ~replacement_key
        .value     = ~replacement_value
        .allocator = allocator
    )!
    if length(.self = &map).count != 1 { abort }
    extracted ::= extract(.self = $&map, .key = &query).result
    if length(.self = &map).count != 0 { abort }
    deinit(.self = $&map, .allocator = allocator)
    match extracted {
        ..none { abort }
        ..some ~payload {
            entry ::= ~payload.value
            if equals(.left = as_view(.self = &entry.key), .right = "key").ok == false { abort }
            if equals(.left = as_view(.self = &entry.value), .right = "second").ok == false {
                abort
            }
        }
    }
}
