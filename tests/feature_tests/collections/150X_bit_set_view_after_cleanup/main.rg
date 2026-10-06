run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    bits ::= BitSet(.count = 1, .allocator = allocator)!
    borrowed ::= as_view(.self = $&bits).view
    deinit(.self = $&bits, .allocator = allocator)
    contains(.self = &borrowed, .index = 0)!
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
