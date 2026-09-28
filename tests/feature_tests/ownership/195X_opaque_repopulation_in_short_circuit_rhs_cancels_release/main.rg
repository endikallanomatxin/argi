unsafe_allocation := #import("../../_support/unsafe_allocation")
Borrowing : Type = (.reference: $&UInt8)

deinit(.self: $&Borrowing) -> () := {}

store_and_return(.slot: $&Borrowing, .reference: $&UInt8) -> (.result: Bool) := {
    slot&.reference = reference
    result = true
}

release_then_maybe_store(.storage: $&Allocation, .slot: $&Borrowing, .reference: $&UInt8, .condition: Bool) -> () := {
    trusted_opaque_mark_empty(.storage = storage)
    value ::= condition and store_and_return(.slot = slot, .reference = reference).result
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    target_result ::= allocate(.self = $&allocator_storage, .size = 1)
    storage_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match storage_result {
                ..error _ { status_code = 2 }
                ..ok ~ storage_payload {
                    storage ::= ~storage_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&storage, .offset = 0).reference).reference
                    initial :: Borrowing = (.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
                    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&storage, .destination = slot, .source = ~initial)
                    trusted_opaque_drop(.slot = slot)
                    release_then_maybe_store(.storage = $&storage, .slot = slot, .reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference, .condition = false)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
