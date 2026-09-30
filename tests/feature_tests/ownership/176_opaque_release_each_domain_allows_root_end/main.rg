unsafe_allocation := import("../../_support/unsafe_allocation")
Borrowing : Type = (
    .reference: $&UInt8
)

deinit(.self: $&Borrowing) -> () := {
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    target_result ::= allocate(.self = $&allocator_storage, .size = 1)
    first_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    second_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match first_result {
                ..error _ { status_code = 2 }
                ..ok ~ first_payload {
                    first ::= ~first_payload
                    match second_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ second_payload {
                            second ::= ~second_payload
                            first_slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&first, .offset = 0).reference).reference
                            second_slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&second, .offset = 0).reference).reference
                            first_value :: Borrowing = (.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
                            second_value :: Borrowing = (.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
                            trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&first, .destination = first_slot, .source = ~first_value)
                            trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&second, .destination = second_slot, .source = ~second_value)
                            trusted_opaque_drop(.slot = first_slot)
                            trusted_opaque_drop(.slot = second_slot)
                            trusted_opaque_mark_empty(.storage = $&first)
                            trusted_opaque_mark_empty(.storage = $&second)
                            deinit(.self = $&target)
                            deinit(.self = $&first)
                            deinit(.self = $&second)
                            status_code = 0
                        }
                    }
                }
            }
        }
    }
}
