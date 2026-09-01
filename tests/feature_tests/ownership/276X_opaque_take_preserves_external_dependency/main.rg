BorrowingOwner : Type = (.allocation: Allocation, .borrowed: $&UInt8)
deinit(.self: $&BorrowingOwner) -> () := { deinit(.self = $&self&.allocation) }

main(.system: System) -> (.status_code: Int32 = 0) := {
    external_result ::= allocate(.self = system.allocator, .size = 1)
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = BorrowingOwner))
    owned_result ::= allocate(.self = system.allocator, .size = 1)
    match external_result {
        ..error _ { status_code = 1 }
        ..ok ~ external_payload {
            external ::= ~external_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    match owned_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ owned_payload {
                            value ::= BorrowingOwner(.allocation = ~owned_payload, .borrowed = external.data)
                            slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: BorrowingOwner)(.base = slots.data).reference
                            trusted_opaque_store_owned_in#(.t: BorrowingOwner, .storage_type: Allocation)(.storage = $&slots, .destination = slot, .source = ~value)
                            taken ::= trusted_opaque_take_owned_in#(.t: BorrowingOwner, .storage_type: Allocation)(.storage = $&slots, .slot = slot)
                            trusted_opaque_release_all(.storage = $&slots)
                            deinit(.self = $&external)
                            observed ::= taken.borrowed&
                            if observed == 255 { status_code = 4 }
                            deinit(.self = $&taken)
                            deinit(.self = $&slots)
                        }
                    }
                }
            }
        }
    }
}
