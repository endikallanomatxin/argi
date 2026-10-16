run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!
    put(.self = $&map, .key = 1, .value = 10, .allocator = allocator)!
    iterator ::= to_rw_entry_iterator(.value = $&map).iterator
    entry ::= next(.self = $&iterator).value
    put(.self = $&map, .key = 1, .value = 20, .allocator = allocator)!
    if entry.value&!= 10 { abort }
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
