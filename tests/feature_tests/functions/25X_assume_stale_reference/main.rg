read(.reference: $&Allocation) -> (.result: UIntNative) := {
    result = reference&.size
}
main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            assume reference ::= $&allocation
            deinit(.self = $&allocation)
            observed ::= read()
        }
    }
}
