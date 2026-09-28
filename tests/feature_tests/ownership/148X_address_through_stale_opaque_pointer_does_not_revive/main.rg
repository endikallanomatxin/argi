unsafe_allocation := #import("../../_support/unsafe_allocation")
Value : Type = (
    .number: UInt8
)

deinit(.self: $&Value) -> () := {
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    first_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Value))
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            slots ::= ~first_payload
            stale_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Value)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference
            value :: Value = (.number = 7)
            trusted_opaque_move_in#(.t: Value, .storage_type: Allocation)(
                .storage = $&slots,
                .destination = stale_slot,
                .source = ~value,
            )
            trusted_opaque_drop(.slot = stale_slot)
            deinit(.self = $&slots)

            second_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Value))
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second_payload {
                    slots = ~second_payload
                    revived ::= $&stale_slot&.number
                    status_code = 0
                    deinit(.self = $&slots)
                }
            }
        }
    }
}
