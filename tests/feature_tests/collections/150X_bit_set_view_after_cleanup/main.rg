main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    bits ::= BitSet(.count = 1, .allocator = allocator)!
    borrowed ::= as_view(.self = $&bits).view
    deinit(.self = $&bits, .allocator = allocator)
    contains(.self = &borrowed, .index = 0)!
}
