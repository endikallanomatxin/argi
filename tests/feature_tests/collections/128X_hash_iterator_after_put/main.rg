main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = allocator
    )!
    put(.self = $&map, .key = 1, .value = 10, .allocator = allocator)!
    iterator ::= to_iterator(.value = &map).iterator
    put(.self = $&map, .key = 1, .value = 20, .allocator = allocator)!
    if has_next(.self = &iterator).ok { abort }
}
