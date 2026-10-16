lookup_mutable#(.Map: Type: MutableTextMapBorrowedLookup#(.Value: UIntNative))(
    .self: $&Map, .key: StringView
) -> (.result: ?$&UIntNative) := {
    result = MutableTextMapBorrowedLookup#(Map).get_mutable_reference(.self = self, .key = key)
}

run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: String, .value: UIntNative, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!
    key ::= format(.value = "café", .allocator = allocator)!
    put(.self = $&map, .key = ~key, .value = 1, .allocator = allocator)!
    if contains(.self = &map, .key = "café").ok == false { abort }
    if contains(.self = &map, .key = "missing").ok { abort }
    match get_mutable_reference(.self = $&map, .key = "café").result {
        ..none { abort }
        ..some borrowed { borrowed.value&= 42 }
    }
    match get_reference(.self = &map, .key = "café").result {
        ..none { abort }
        ..some borrowed { if borrowed.value&!= 42 { abort } }
    }
    match lookup_mutable(.self = $&map, .key = "missing").result {
        ..none {} ..some _ { abort }
    }
    match lookup_mutable(.self = $&map, .key = "café").result {
        ..none { abort }
        ..some borrowed { if borrowed.value&!= 42 { abort } }
    }
    empty ::= format(.value = "", .allocator = allocator)!
    put(.self = $&map, .key = ~empty, .value = 0, .allocator = allocator)!
    if contains(.self = &map, .key = "").ok == false { abort }
    if length(.self = &map).count != 2 { abort }
    found :: ?&UIntNative = ..none
    {
        query ::= format(.value = "café", .allocator = allocator)!
        found = get_reference(.self = &map, .key = view(.self = &query).view).result
    }
    match found {
        ..none { abort }
        ..some borrowed { if borrowed.value&!= 42 { abort } }
    }

}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
