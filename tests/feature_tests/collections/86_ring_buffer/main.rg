main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    ring ::= unwrap_or_abort(.value = RingBuffer#(.t: Int32)(.capacity = 3, .allocator = allocator))
    if is(.value = pop(.self = $&ring).result, .variant = ..error) == false { abort }
    round :: Int32 = 0
    while round < 10 {
        unwrap_or_abort(.value = push(.self = $&ring, .value = round, .allocator = allocator))
        unwrap_or_abort(.value = push(.self = $&ring, .value = round + 1, .allocator = allocator))
        if unwrap_or_abort(.value = pop(.self = $&ring)) != round { abort }
        unwrap_or_abort(.value = push(.self = $&ring, .value = round + 2, .allocator = allocator))
        unwrap_or_abort(.value = push(.self = $&ring, .value = round + 3, .allocator = allocator))
        if is(.value = push(.self = $&ring, .value = 99, .allocator = allocator), .variant = ..error) == false { abort }
        if length(.self = &ring).count != 3 or capacity(.self = &ring).count != 3 { abort }
        if unwrap_or_abort(.value = get_ro_ref(.self = &ring, .index = 0))& != round + 1 { abort }
        if contains(.self = &ring, .value = round + 3).ok == false { abort }
        if is(.value = get_ro_ref(.self = &ring, .index = 3), .variant = ..error) == false { abort }
        if unwrap_or_abort(.value = pop(.self = $&ring)) != round + 1 { abort }
        if unwrap_or_abort(.value = pop(.self = $&ring)) != round + 2 { abort }
        if unwrap_or_abort(.value = pop(.self = $&ring)) != round + 3 { abort }
        round = round + 1
    }
    deinit(.self = $&ring, .allocator = allocator)
}
