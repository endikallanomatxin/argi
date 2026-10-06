run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy)(
        .policy    = StringHashPolicy()
        .allocator = allocator
    )!
    key ::= format(.value = "key", .allocator = allocator)!
    put(.self = $&map, .key = ~key, .value = 1, .allocator = allocator)!
    match get_ref(.self = $&map, .key = "key").result {
        ..none { abort }
        ..some borrowed {
            other ::= format(.value = "other", .allocator = allocator)!
            put(.self = $&map, .key = ~other, .value = 2, .allocator = allocator)!
            if borrowed.value&== 1 { abort }
        }
    }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
