main(.system: System) -> () := {
    assume allocator := system.page_allocator
    queue ::= unwrap_or_abort(.value = Deque#(.t: Int32)(.capacity = 1))
    unwrap_or_abort(.value = push_back(.self = $&queue, .value = 1))
    borrowed ::= unwrap_or_abort(.value = get_ro_ref(.self = &queue, .index = 0))
    unwrap_or_abort(.value = push_front(.self = $&queue, .value = 2))
    observed ::= borrowed&
}
