Borrowing : Type = (
    .reference: &UInt8
)

external :: UInt8 = 7

deinit(.self: $&Borrowing) -> () := {
}

store_borrow(
    .storage: $&Allocation,
    .slot: $&Borrowing,
    .target: &UInt8,
) -> () := {
    local :: Borrowing = (.reference = target)
    trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(
        .storage = storage,
        .destination = slot,
        .source = ~local,
    )
}

main(.system: System) -> (.status_code: Int32) := {
    unrelated_result ::= allocate(.self = system.allocator, .size = 1)
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match unrelated_result {
        ..error _ { status_code = 1 }
        ..ok ~ unrelated_payload {
            unrelated ::= ~unrelated_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = slots.data).reference
                    store_borrow(.storage = $&slots, .slot = slot, .target = &external)
                    deinit(.self = $&unrelated)
                    trusted_opaque_drop_owned(.slot = slot)
                    deinit(.self = $&slots)
                    status_code = 0
                }
            }
        }
    }
}
