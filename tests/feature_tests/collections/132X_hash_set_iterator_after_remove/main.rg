run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    set ::= HashSet#(.key: Int32, .policy: Int32HashPolicy)(
        .policy    = Int32HashPolicy()
        .allocator = allocator
    )!
    insert(.self = $&set, .key = 1, .allocator = allocator)!
    iterator ::= to_iterator(.value = &set).iterator
    remove(.self = $&set, .key = 1, .allocator = allocator)
    if has_next(.self = &iterator).ok { abort }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
