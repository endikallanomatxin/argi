main(.system: System, .condition: Bool = false) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
    ..error _ { status_code = 1 }
    ..ok ~ payload {
    owner ::= ~payload

    if condition {
        moved ::= ~owner
        if moved.size == 1 {
            status_code = 0
        }
    }

    status_code = 0
    }
    }
}
