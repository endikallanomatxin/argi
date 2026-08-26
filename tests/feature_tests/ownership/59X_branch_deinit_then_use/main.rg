main(.system: System, .condition: Bool = false) -> (.status_code: Int32) := {
    allocation ::= allocate_owned(.self = system.allocator, .size = 1)

    if condition {
        deinit(.self = $&allocation)
    }

    if allocation.size == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
}
