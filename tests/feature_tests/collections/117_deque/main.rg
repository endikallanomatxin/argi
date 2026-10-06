run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    queue ::= Deque#(.t: Int32)(.capacity = 2)!
    push_back(.self = $&queue, .value = 1)!
    push_back(.self = $&queue, .value = 2)!
    if pop_front(.self = $&queue)! != 1 { abort }
    push_back(.self = $&queue, .value = 3)!
    push_front(.self = $&queue, .value = 0)!
    if length(.self = &queue).count != 3 or capacity(.self = &queue).count != 4 { abort }
    if [
        get(.self = &queue, .index = 0)! != 0
        or get(.self = &queue, .index = 1)! != 2
        or get(.self = &queue, .index = 2)! != 3
    ] { abort }
    reference ::= get_rw_ref(.self = $&queue, .index = 1)!
    reference&= 20
    if pop_back(.self = $&queue)! != 3 { abort }
    if pop_front(.self = $&queue)! != 0 { abort }
    if pop_back(.self = $&queue)! != 20 { abort }
    match pop_front(.self = $&queue) {
        ..ok _ { abort } ..error error { if error.reason != ..empty { abort } }
    }
    reserve(.self = $&queue, .capacity = 9)!
    if capacity(.self = &queue).count != 9 { abort }
    index :: Int32 = 0
    while index < 40 {
        push_front(.self = $&queue, .value = index)!
        index = index + 1
    }
    index = 0
    while index < 40 {
        if pop_back(.self = $&queue)! != index { abort }
        index = index + 1
    }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
