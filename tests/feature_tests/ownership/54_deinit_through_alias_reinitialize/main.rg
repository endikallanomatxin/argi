main(.system: System) -> (.status_code: Int32) := {
    allocation ::= allocate(.self = system.allocator, .size = 1)
    a ::= $&allocation
    b ::= $&allocation

    deinit(.self = a)

    b& = allocate(.self = system.allocator, .size = 1)
    if b&.size == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
}
