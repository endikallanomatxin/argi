Tracked : Type = (.id: Int32)
drops :: Int32 = 0
Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Tracked)(.capacity = 4))
    first ::= Tracked(.id = 1)
    second ::= Tracked(.id = 2)
    middle ::= Tracked(.id = 3)
    push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~first)
    push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~second)
    inserted ::= unwrap_or_abort(.value = insert#(.t: Tracked)(.allocator = allocator, .self = $&array, .i = 1, .value = ~middle).result)
    removed ::= unwrap_or_abort(.value = remove#(.t: Tracked)(.self = $&array, .i = 1).result)
    if removed.id != 3 or drops != 0 { status_code = 1 }
    deinit(.self = $&removed)
    replacement ::= Tracked(.id = 4)
    replaced ::= unwrap_or_abort(.value = set#(.t: Tracked)(.self = $&array, .index = 0, .value = ~replacement, .allocator = allocator).result)
    fresh ::= unwrap_or_abort(.value = get_ro_ref#(.t: Tracked)(.self = &array, .index = 0).result)
    if fresh&.id != 4 or drops != 2 { status_code = 2 }
    last ::= unwrap_or_abort(.value = pop#(.t: Tracked)(.self = $&array).result)
    if last.id != 2 { status_code = 3 }
    deinit(.self = $&last)
    remaining ::= unwrap_or_abort(.value = pop#(.t: Tracked)(.self = $&array).result)
    if remaining.id != 4 { status_code = 4 }
    deinit(.self = $&remaining)
    empty ::= pop#(.t: Tracked)(.self = $&array).result
    if is(.value = empty, .variant = ..error) == false { status_code = 5 }
    deinit#(.t: Tracked)(.self = $&array)
    if drops != 4 { status_code = 6 }
}
