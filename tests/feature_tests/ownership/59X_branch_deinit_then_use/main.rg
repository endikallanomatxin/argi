main(.system: System, .condition: Bool = false) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
    ..error _ { status_code = 2 }
    ..ok ~ payload {
    allocation ::= ~payload

    if condition {
        deinit(.self = $&allocation)
    }

    if allocation.size == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
    }
    }
}
