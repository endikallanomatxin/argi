main := (.system: System) -> (.status_code: Int32 = 1) {

    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    bits ::= BitSet(.count = 1, .allocator = allocator)!!!
    borrowed ::= view(.self = $&bits).view
    deinit(.self = $&bits)
    contains_bit(.self = &borrowed, .index = 0)!!!
    status_code = 0
}
