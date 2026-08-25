main(.system: System) -> (.status_code: Int32) := {
    allocation ::= allocate_owned(.self = system.allocator, .size = 1)
    reference ::= allocation.data

    deinit(.self = $&allocation, .allocator = system.allocator)
    if reference& == 0 {
        status_code = 0
    }
}
