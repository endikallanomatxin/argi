main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy)(
        .policy    = StringHashPolicy()
        .allocator = allocator
    )!
    key ::= format(.value = "café", .allocator = allocator)!
    put(.self = $&map, .key = ~key, .value = 1, .allocator = allocator)!
    if contains(.self = &map, .key = "café").ok == false { abort }
    if contains(.self = &map, .key = "missing").ok { abort }
    match get_ref(.self = $&map, .key = "café").result {
        ..none { abort }
        ..some borrowed { borrowed.value&= 42 }
    }
    match get_ro_ref(.self = &map, .key = "café").result {
        ..none { abort }
        ..some borrowed { if borrowed.value&!= 42 { abort } }
    }
    match get_ref(.self = $&map, .key = "missing").result { ..none {} ..some _ { abort } }
    empty ::= format(.value = "", .allocator = allocator)!
    put(.self = $&map, .key = ~empty, .value = 0, .allocator = allocator)!
    if contains(.self = &map, .key = "").ok == false { abort }
    if length(.self = &map).count != 2 { abort }
    found :: ?&UIntNative = ..none
    {
        query ::= format(.value = "café", .allocator = allocator)!
        found = get_ro_ref(.self = &map, .key = as_view(.self = &query).view).result
    }
    match found {
        ..none { abort }
        ..some borrowed { if borrowed.value&!= 42 { abort } }
    }

}
