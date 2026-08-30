Result : Type = (
    ..ok Allocation
    ..error Int32
)

read(.pointer: $&UInt8) -> (.value: UInt8) := {
    value = pointer&
}

main(.system: System) -> (.status_code: Int32 = 1) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 2 }
        ..ok ~ allocation {
            stale ::= allocation.data
            result : Result = ..ok ~allocation
            payload ::= ~result..ok

            deinit(.self = $&payload)
            observed ::= read(.pointer = stale)
            if observed == 0 { status_code = 0 } else { status_code = 3 }
        }
    }
}
