main(.system: System) -> () := {
    assume allocator := system.page_allocator
    queue ::= unwrap_or_abort(.value = Deque#(.t: Int32)(.capacity = 2))
    unwrap_or_abort(.value = push_front(.self = $&queue, .value = 1))
    borrowed ::= unwrap_or_abort(.value = get_rw_ref(.self = $&queue, .index = 0))
    removed ::= unwrap_or_abort(.value = pop_back(.self = $&queue))
    borrowed&= 2
}
