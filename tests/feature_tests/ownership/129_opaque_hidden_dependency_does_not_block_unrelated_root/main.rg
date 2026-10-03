unsafe_allocation := import("../../_support/unsafe_allocation")
Borrowing : Type = (
    .reference: &Int32
)

external :: Int32 = 7

Borrowing deinit(.self: $&Borrowing) -> () := {
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    unrelated_result ::= allocate(.self = $&allocator_storage, .size = 1)
    slots_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    match unrelated_result {
        ..error _ { status_code = 1 }
        ..ok ~ unrelated_payload {
            unrelated ::= ~unrelated_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference
                    hidden :: Borrowing = (.reference = &external)
                    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
                        .storage = $&slots,
                        .destination = slot,
                        .source = ~hidden,
                    )

                    deinit(.self = $&unrelated)
                    trusted_opaque_drop(.slot = slot)
                    deinit(.self = $&slots)
                    status_code = 0
                }
            }
        }
    }
}
