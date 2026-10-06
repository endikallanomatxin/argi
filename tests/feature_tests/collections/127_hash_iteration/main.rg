run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = allocator
    )!
    for entry in map { abort }
    index :: Int32 = 0
    while index < 40 {
        put(.self = $&map, .key = index, .value = index * 3, .allocator = allocator)!
        index = index + 1
    }
    if remove(.self = $&map, .key = 1, .allocator = allocator).removed == false { abort }
    sum :: Int32 = 0
    count :: UIntNative = 0
    for entry in map {
        if entry.value != entry.key * 3 { abort }
        sum = sum + entry.key
        count = count + 1
    }
    if sum != 779 or count != 39 { abort }
    keys ::= to_key_iterator(.value = &map).iterator
    sum = 0
    while has_next(.self = &keys).ok { sum = sum + next(.self = $&keys).value }
    if sum != 779 { abort }
    values ::= to_value_iterator(.value = &map).iterator
    sum = 0
    while has_next(.self = &values).ok { sum = sum + next(.self = $&values).value }
    if sum != 2337 { abort }
    borrowed ::= to_ro_entry_iterator(.value = &map).iterator
    while has_next(.self = &borrowed).ok {
        entry ::= next(.self = $&borrowed).value
        if entry.value&!= entry.key&* 3 { abort }
    }
    mutable ::= to_rw_entry_iterator(.value = $&map).iterator
    while has_next(.self = &mutable).ok {
        entry ::= next(.self = $&mutable).value
        entry.value&= entry.value&+ 1
    }
    for entry in map { if entry.value != entry.key * 3 + 1 { abort } }
    set ::= HashSet#(.key: Int32, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = allocator
    )!
    for key in set { abort }
    insert(.self = $&set, .key = 2, .allocator = allocator)!
    insert(.self = $&set, .key = 4, .allocator = allocator)!
    insert(.self = $&set, .key = 6, .allocator = allocator)!
    remove(.self = $&set, .key = 4, .allocator = allocator)
    sum = 0
    for key in set { sum = sum + key }
    if sum != 8 { abort }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
