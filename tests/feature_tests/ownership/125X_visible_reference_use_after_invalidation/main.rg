main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            visible ::= allocation.data
            deinit(.self = $&allocation)

            -- Invalidation itself was legal; this use is not.
            status_code = 0
            if visible& == 0 {
                status_code = 2
            }
        }
    }
}
