unsafe_allocation := import("../../_support/unsafe_allocation")
AddressSensitive : Type = (
    .reference: Nullable#(.t: $&UInt8)
)

deinit(.self: $&AddressSensitive) -> () := {
}

set_reference(.slot: $&AddressSensitive, .target: $&UInt8) -> () := {
    slot&.reference = ..some(.value = target)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    target_result ::= allocate(.self = $&allocator_storage, .size = 1)
    slots_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = AddressSensitive))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: AddressSensitive)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference
                    value :: AddressSensitive = (.reference = ..none)
                    trusted_opaque_move_in#(.t: AddressSensitive, .storage_type: Allocation)(
                        .storage = $&slots,
                        .destination = slot,
                        .source = ~value,
                    )

                    set_reference(.slot = slot, .target = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
