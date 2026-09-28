unsafe_allocation := #import("../../_support/unsafe_allocation")
Borrowing : Type = (
    .reference: &Int32
)

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    external :: Int32 = 7
    value :: Borrowing = (.reference = &external)
    slots_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference

            -- Precision is discarded at the slot boundary, but the dependency
            -- on `external` survives in the storage-level opaque summary.
            trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
                .storage = $&slots,
                .destination = slot,
                .source = ~value,
            )
            deinit(.self = $&slots)
            status_code = 0
        }
    }
}
