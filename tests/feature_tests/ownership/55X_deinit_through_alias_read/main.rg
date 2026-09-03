main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
    ..error _ { status_code = 1 }
    ..ok ~ payload {
    allocation ::= ~payload
    a ::= $&allocation
    b ::= $&allocation

    deinit(.self = a)
    if b&.size == 1 {
        status_code = 0
    }
    }
    }
}
