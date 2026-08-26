main(.system: System) -> (.status_code: Int32) := {
    a ::= allocate(.self = system.allocator, .size = size_of(.type = Allocation))
    b ::= allocate(.self = system.allocator, .size = size_of(.type = Allocation))
    slot_a ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = a.data).reference
    slot_b ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = b.data).reference

    slot_a& = ~b
    slot_b& = ~a
    status_code = 0
}
