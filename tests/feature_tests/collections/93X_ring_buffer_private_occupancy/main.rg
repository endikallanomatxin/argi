main(.system: System) -> () := {
    ring ::= unwrap_or_abort(.value = RingBuffer#(.t: Int32)(.capacity = 1, .allocator = system.page_allocator))
    ring._head = 1
    deinit(.self = $&ring, .allocator = system.page_allocator)
}
