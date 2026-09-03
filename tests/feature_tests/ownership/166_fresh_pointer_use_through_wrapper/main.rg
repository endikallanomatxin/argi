read(.p: $&UInt8) -> (.result: UInt8) := {
    result = p&
}

main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            observed ::= read(.p = allocation.data).result
            if observed == 0 { status_code = 0 } else { status_code = 2 }
            deinit(.self = $&allocation)
        }
    }
}
