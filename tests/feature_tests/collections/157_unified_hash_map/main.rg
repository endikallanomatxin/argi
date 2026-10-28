main := () -> (.status_code: Int32 = 1) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= CAllocator(.ffi = ffi)
    assume allocator ::= $&allocator_storage
    map ::= unwrap_or_abort(
        .value = HashMap#(.key: String, .value: Int32, .policy: StandardHashPolicy)(
            .policy = StandardHashPolicy()
        )
    )
    key ::= unwrap_or_abort(.value = format(.value = "key"))
    unwrap_or_abort(.value = put($&map, .key = ~key, .value = 41))
    query ::= unwrap_or_abort(.value = format(.value = "key"))
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
    owners ::= unwrap_or_abort(
        .value = HashMap#(.key: Int32, .value: String, .policy: StandardHashPolicy)(
            .policy = StandardHashPolicy()
        )
    )
    text ::= unwrap_or_abort(.value = format(.value = "value"))
    unwrap_or_abort(.value = put($&owners, .key = 3, .value = ~text))
    keys ::= to_key_iterator(.value = &owners).iterator
    if has_next(&keys).ok == false { abort }
    if next($&keys).value != 3 { abort }
    for entry in owners {
        if entry.key&!= 3 or view(entry.value) != "value" { abort }
    }
    scalars ::= unwrap_or_abort(
        .value = HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
            .policy = StandardHashPolicy()
        )
    )
    unwrap_or_abort(.value = put($&scalars, .key = 7, .value = 9))
    for entry in scalars {
        if entry.key&!= 7 or entry.value&!= 9 { abort }
    }
    status_code = 0
}
