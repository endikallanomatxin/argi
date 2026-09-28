main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
    ..error _ { status_code = 1 }
    ..ok ~ payload {
    allocation ::= ~payload
    reference ::= trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference

    deinit(.self = $&allocation)
    if reference& == 0 {
        status_code = 0
    }
    }
    }
}
