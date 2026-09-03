main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            visible ::= allocation.data

            -- Merely keeping a precise reference alive does not prevent the
            -- operation that ends its root. The checker rejects only a later
            -- use of `visible` (covered by the companion negative test).
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
}
