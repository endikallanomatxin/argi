run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    bits ::= BitSet(.count = 17, .allocator = allocator)!
    if length(.self = &bits).count != 17 or count_set(.self = &bits).count != 0 { abort }
    set_bit(.self = $&bits, .index = 0)!
    set_bit(.self = $&bits, .index = 16)!
    if count_set(.self = &bits).count != 2 { abort }
    {
        borrowed ::= as_view(.self = $&bits).view
        set_bit(.self = $&borrowed, .index = 8)!
    }
    if count_set(.self = &bits).count != 3 { abort }
    if contains_bit(.self = &bits, .index = 8)! == false { abort }
    match set_bit(.self = $&bits, .index = 17) { ..ok _ { abort } ..error _ {} }
    if count_set(.self = &bits).count != 3 { abort }
    empty ::= BitSet(.count = 0, .allocator = allocator)!
    if count_set(.self = &empty).count != 0 { abort }
}

main#(.WriterType: Type: Writer#(WriterType))(.system: System, .writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
