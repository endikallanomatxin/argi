inner(.p: $&UInt8) -> (.result: UInt8) := {
    result = p&
}

outer(.p: $&UInt8) -> (.result: UInt8) := {
    result = inner(.p = p).result
}

main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            pointer ::= allocation.data
            deinit(.self = $&allocation)
            observed ::= outer(.p = pointer).result
            if observed == 0 { status_code = 0 } else { status_code = 2 }
        }
    }
}
