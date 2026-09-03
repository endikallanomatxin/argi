main(.system: System) -> (.status_code: Int32) := {
    result_a ::= allocate(.self = system.allocator, .size = size_of(.type = Allocation))
    match result_a {
    ..error _ { status_code = 1 }
    ..ok ~ payload_a {
    a ::= ~payload_a
    result_b ::= allocate(.self = system.allocator, .size = size_of(.type = Allocation))
    match result_b {
    ..error _ { status_code = 2 }
    ..ok ~ payload_b {
    b ::= ~payload_b
    slot_a ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = a.data).reference
    slot_b ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = b.data).reference

    slot_a& = ~b
    slot_b& = ~a
    status_code = 0
    }
    }
    }
    }
}
