Owner : Type = (.allocation: Allocation)
deinit(.self: $&Owner) -> () := { deinit(.self = $&self&.allocation) }

store_one(.storage: $&Allocation, .slot: $&Owner, .value: Owner) -> () := {
    trusted_opaque_move_in#(.t: Owner, .storage_type: Allocation)(.storage = storage, .destination = slot, .source = ~value)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = Owner))
    owned_result ::= allocate(.self = system.allocator, .size = 1)
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            match owned_result {
                ..error _ { status_code = 2 }
                ..ok ~ owned_payload {
                    value ::= Owner(.allocation = ~owned_payload)
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Owner)(.base = slots.data).reference
                    store_one(.storage = $&slots, .slot = slot, .value = ~value)
                    trusted_opaque_drop(.slot = slot)
                    trusted_opaque_mark_empty(.storage = $&slots)
                    deinit(.self = $&slots)
                }
            }
        }
    }
}
