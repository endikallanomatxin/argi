unsafe_allocation := import("../../_support/unsafe_allocation")
TrackedBorrowing : Type = (
    .id: Int32
    .reference: &UInt8
)

external :: UInt8 = 9
drops :: Int32 = 0

TrackedBorrowing deinit(.self: $&TrackedBorrowing) -> () := {
    drops = drops + 1
}

store_local(
    .storage: $&Allocation,
    .slot: $&TrackedBorrowing,
    .target: &UInt8,
) -> () := {
    local :: TrackedBorrowing = (
        .id = 1,
        .reference = target,
    )
    trusted_opaque_move_in#(.t: TrackedBorrowing, .storage_type: Allocation)(
        .storage = storage,
        .destination = slot,
        .source = ~local,
    )
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    slots_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = TrackedBorrowing))
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: TrackedBorrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference
            store_local(
                .storage = $&slots,
                .slot = slot,
                .target = &external,
            )
            trusted_opaque_drop(.slot = slot)
            deinit(.self = $&slots)
            if drops == 1 {
                status_code = 0
            } else {
                status_code = 3
            }
        }
    }
}
