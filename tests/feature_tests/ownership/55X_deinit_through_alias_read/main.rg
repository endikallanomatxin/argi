main(.system: System) -> (.status_code: Int32) := {
    allocation ::= allocate_owned(.self = system.allocator, .size = 1)
    a ::= $&allocation
    b ::= $&allocation

    deinit(.self = a)
    if b&.size == 1 {
        status_code = 0
    }
}
