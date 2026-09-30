unsafe_allocation := import("../../_support/unsafe_allocation")
Borrowing : Type = (
    .reference: $&UInt8
)

external :: UInt8 = 7

deinit(.self: $&Borrowing) -> () := {
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocation_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    match allocation_result {
        ..error _ { status_code = 1 }
        ..ok ~ allocation_payload {
            storage ::= ~allocation_payload
            slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&storage, .offset = 0).reference).reference
            value :: Borrowing = (.reference = $&external)

            trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
                .storage = $&storage,
                .destination = slot,
                .source = ~value,
            )
            extracted_mut ::= slot&.reference
            extracted ::= read_reference(.base = extracted_mut).reference

            trusted_opaque_drop(.slot = slot)
            deinit(.self = $&storage)

            observed ::= extracted&
            if observed == 7 {
                status_code = 0
            } else {
                status_code = 2
            }
        }
    }
}
