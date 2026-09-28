unsafe_allocation := #import("../../_support/unsafe_allocation")
Borrowing : Type = (
    .reference: $&UInt8
)

store_inner(
    .storage: $&Allocation,
    .slot: $&Borrowing,
    .target: $&UInt8,
) -> () := {
    local :: Borrowing = (.reference = target)
    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
        .storage = storage,
        .destination = slot,
        .source = ~local,
    )
}

store_outer(
    .storage: $&Allocation,
    .slot: $&Borrowing,
    .target: $&UInt8,
) -> () := {
    store_inner(.storage = storage, .slot = slot, .target = target)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    target_result ::= allocate(.self = $&allocator_storage, .size = 1)
    slots_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference
                    store_outer(.storage = $&slots, .slot = slot, .target = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
