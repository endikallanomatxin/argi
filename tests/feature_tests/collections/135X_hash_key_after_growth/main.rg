run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!
    put(.self = $&map, .key = 1, .value = 10, .allocator = allocator)!
    iterator ::= to_ro_entry_iterator(.value = &map).iterator
    entry ::= next(.self = $&iterator).value
    index :: Int32 = 2
    while index < 20 {
        put(.self = $&map, .key = index, .value = index, .allocator = allocator)!
        index = index + 1
    }
    if entry.key&!= 1 { abort }
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
