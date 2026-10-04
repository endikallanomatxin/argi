main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= OwnedHashMap#(.key: Int32, .value: String, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = allocator
    )!
    text ::= format(.value = "owned", .allocator = allocator)!
    put(.self = $&map, .key = 1, .value = ~text, .allocator = allocator)!
    query :: Int32 = 1
    iterator ::= to_iterator(.value = &map).iterator
    entry ::= next(.self = $&iterator).value
    entry.key&= 2
}
