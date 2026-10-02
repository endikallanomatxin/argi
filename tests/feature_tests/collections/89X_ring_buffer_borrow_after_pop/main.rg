main(.system: System) -> () := {
    ring ::= unwrap_or_abort(.value = RingBuffer#(.t: Int32)(.capacity = 2, .allocator = system.page_allocator))
    unwrap_or_abort(.value = push(.self = $&ring, .value = 7, .allocator = system.page_allocator))
    borrowed ::= unwrap_or_abort(.value = get_ro_ref(.self = &ring, .index = 0))
    removed ::= unwrap_or_abort(.value = pop(.self = $&ring))
    observed ::= borrowed&
    deinit(.self = $&ring, .allocator = system.page_allocator)
}
