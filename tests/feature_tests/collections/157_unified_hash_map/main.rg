run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: String, .value: Int32, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy()
    )!
    key ::= format(.value = "key")!
    put($&map, .key = ~key, .value = 41)!
    query ::= format(.value = "key")!
    match get(&map, .key = view(&query)).result {
        ..none { abort }
        ..some item { if item.value != 41 { abort } }
    }
    values ::= to_value_iterator(.value = &map).iterator
    if has_next(&values).ok == false { abort }
    if next($&values).value != 41 { abort }
    mutable ::= to_rw_entry_iterator(.value = $&map).iterator
    entry ::= next($&mutable).value
    entry.value&= 42
    if contains(&map, .key = "key").ok == false { abort }
    extracted ::= extract($&map, .key = view(&query)).result
    deinit($&map)
    match extracted {
        ..none { abort }
        ..some ~payload {
            entry ::= ~payload.value
            if view(&entry.key) != "key" or entry.value != 42 { abort }
        }
    }
    owners ::= HashMap#(.key: Int32, .value: String, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy()
    )!
    text ::= format(.value = "value")!
    put($&owners, .key = 3, .value = ~text)!
    keys ::= to_key_iterator(.value = &owners).iterator
    if has_next(&keys).ok == false { abort }
    if next($&keys).value != 3 { abort }
    for entry in owners {
        if entry.key&!= 3 or view(entry.value) != "value" { abort }
    }
    scalars ::= HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy()
    )!
    put($&scalars, .key = 7, .value = 9)!
    for entry in scalars {
        if entry.key&!= 7 or entry.value&!= 9 { abort }
    }
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
