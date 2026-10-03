Tracked : Type = (.id: Int32)
Tracked deinit(.self: $&Tracked) -> () := {}
main(.system: System) -> () := {
    ring ::= unwrap_or_abort(.value = RingBuffer#(.t: Tracked)(.capacity = 1, .allocator = system.page_allocator))
    item ::= Tracked(.id = 1)
    unwrap_or_abort(.value = push(.self = $&ring, .value = ~item, .allocator = system.page_allocator))
    observed ::= item.id
    deinit(.self = $&ring, .allocator = system.page_allocator)
}
