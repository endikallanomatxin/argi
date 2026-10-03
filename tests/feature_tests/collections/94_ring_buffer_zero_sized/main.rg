Empty : Type = ()
drops :: Int32 = 0
Empty deinit(.self: $&Empty) -> () := { drops = drops + 1 }
main(.system: System) -> (.status_code: Int32 = 0) := {
    ring ::= unwrap_or_abort(.value = RingBuffer#(.t: Empty)(.capacity = 2, .allocator = system.page_allocator))
    a ::= Empty()
    b ::= Empty()
    rejected ::= Empty()
    unwrap_or_abort(.value = push(.self = $&ring, .value = ~a, .allocator = system.page_allocator))
    unwrap_or_abort(.value = push(.self = $&ring, .value = ~b, .allocator = system.page_allocator))
    if is(.value = push(.self = $&ring, .value = ~rejected, .allocator = system.page_allocator), .variant = ..error) == false { abort }
    popped ::= unwrap_or_abort(.value = pop(.self = $&ring))
    deinit(.self = $&ring, .allocator = system.page_allocator)
    if drops != 2 { abort }
    deinit(.self = $&popped)
    if drops != 3 { abort }
}
