Borrowing : Type = (
    .reference: $&UInt8
)

store_borrow(
    .storage: $&Allocation,
    .slot: $&Borrowing,
    .value: Borrowing,
) -> () := {
    trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(
        .storage = storage,
        .destination = slot,
        .source = ~value,
    )
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = slots.data).reference
                    hidden :: Borrowing = (.reference = target.data)
                    store_borrow(.storage = $&slots, .slot = slot, .value = ~hidden)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
