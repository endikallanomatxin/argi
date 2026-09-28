unsafe_allocation := #import("../../_support/unsafe_allocation")
Observer : Type = (.reference: $&UInt8)
Wrapper : Type = (.observer: Observer)

deinit(.self: $&Observer) -> () := {
    observed ::= self&.reference&
}

observe_on_exit(.reference: $&UInt8) -> () := {
    wrapper ::= Wrapper(.observer = Observer(.reference = reference))
}

main(.system: System) -> (.status_code: Int32) := {
    result ::= allocate(.self = system.allocator, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            stale ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference
            deinit(.self = $&allocation)
            observe_on_exit(.reference = stale)
            status_code = 0
        }
    }
}
