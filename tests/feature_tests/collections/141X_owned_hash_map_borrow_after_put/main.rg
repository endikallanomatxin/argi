main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= OwnedHashMap#(.key: Int32, .value: String, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = allocator
    )!
    text ::= format(.value = "owned", .allocator = allocator)!
    put(.self = $&map, .key = 1, .value = ~text, .allocator = allocator)!
    query :: Int32 = 1
    match get_ro_ref(.self = &map, .key = &query).result {
        ..none { abort }
        ..some borrowed {
            text ::= format(.value = "new", .allocator = allocator)!
            put(.self = $&map, .key = 1, .value = ~text, .allocator = allocator)!
            as_view(.self = borrowed.value)
        }
    }
}
