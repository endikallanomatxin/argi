main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
    ..error _ { status_code = 2 }
    ..ok ~ payload {
    allocation ::= ~payload
    a ::= $&allocation
    b ::= $&allocation

    deinit(.self = a)

    replacement ::= allocate(.self = system.allocator, .size = 1)
    match replacement {
    ..error _ { status_code = 3 }
    ..ok ~ replacement_payload {
    b& = ~replacement_payload
    if b&.size == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
    }
    }
    }
    }
}
