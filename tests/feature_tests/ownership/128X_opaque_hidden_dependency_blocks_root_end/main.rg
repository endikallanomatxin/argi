unsafe_allocation := #import("../../_support/unsafe_allocation")
Borrowing : Type = (
    .reference: $&UInt8
)

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
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
                    hidden :: Borrowing = (.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
                    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
                        .storage = $&slots,
                        .destination = slot,
                        .source = ~hidden,
                    )

                    -- The reference can no longer be checked individually, so
                    -- ending its target must be rejected at this point.
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
