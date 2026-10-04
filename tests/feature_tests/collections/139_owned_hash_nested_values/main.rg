Tracked: Type = (.id: Int32)

drops :: Int32 = 0

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

Wrapper: Type = (.tracked: Tracked, .text: String)

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= OwnedHashMap#(.key: Int32, .value: Wrapper, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = allocator
    )!
    index :: Int32 = 0
    while index < 20 {
        text ::= format(.value = "owned", .allocator = allocator)!
        put(
            .self      = $&map
            .key       = index
            .value     = Wrapper(.tracked = Tracked(.id = index), .text = ~text)
            .allocator = allocator
        )!
        index = index + 1
    }
    if drops != 0 { abort }
    text ::= format(.value = "replacement", .allocator = allocator)!
    put(
        .self      = $&map
        .key       = 0
        .value     = Wrapper(.tracked = Tracked(.id = 100), .text = ~text)
        .allocator = allocator
    )!
    if drops != 1 { abort }
    query :: Int32 = 1
    remove(.self = $&map, .key = &query, .allocator = allocator)
    if drops != 2 { abort }
    deinit(.self = $&map, .allocator = allocator)
    if drops != 21 { abort }
}
