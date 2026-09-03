inner#(.t: Type)(.slot: $&t, .value: t) -> () := {
    trusted_opaque_move#(.t: t)(.destination = slot, .source = ~value)
}

outer#(.t: Type)(.slot: $&t, .value: t) -> () := {
    inner#(.t: t)(.slot = slot, .value = ~value)
}

main(.system: System) -> (.status_code: Int32) := {
    source_result ::= allocate(.self = system.allocator, .size = 1)
    slot_result ::= allocate(.self = system.allocator, .size = size_of(.type = Allocation))

    match source_result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            match slot_result {
                ..error _ { status_code = 2 }
                ..ok ~ slot_payload {
                    slot_allocation ::= ~slot_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = slot_allocation.data).reference
                    outer#(.t: Allocation)(.slot = slot, .value = ~allocation)
                    trusted_opaque_drop#(.t: Allocation)(.slot = slot)
                    deinit(.self = $&slot_allocation)
                    status_code = 0
                }
            }
        }
    }
}
