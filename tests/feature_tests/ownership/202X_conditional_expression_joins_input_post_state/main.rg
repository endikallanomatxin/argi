consume_and_return(.allocation: $&Allocation) -> (.result: Bool) := {
    deinit(.self = allocation)
    result = true
}

maybe_consume(.allocation: $&Allocation, .condition: Bool) -> () := {
    value ::= condition and consume_and_return(.allocation = allocation).result
}

main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            maybe_consume(.allocation = $&allocation, .condition = false)
            if allocation.size == 1 {
                status_code = 0
            } else {
                status_code = 2
            }
        }
    }
}
