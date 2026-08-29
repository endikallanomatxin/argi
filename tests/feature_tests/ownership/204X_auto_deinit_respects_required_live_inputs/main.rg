Observer : Type = (.reference: $&UInt8)

deinit(.self: $&Observer) -> () := {
    observed ::= self&.reference&
}

main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            if 1 == 1 {
                observer ::= Observer(.reference = allocation.data)
                deinit(.self = $&allocation)
            }
            status_code = 0
        }
    }
}
