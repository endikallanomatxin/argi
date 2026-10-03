unsafe_allocation := import("../../_support/unsafe_allocation")
AddressSensitive : Type = (
    .next: Nullable#(.t: $&UInt8)
)

AddressSensitive deinit(.self: $&AddressSensitive) -> () := {
}

set_next(.slot: $&AddressSensitive, .target: $&UInt8) -> () := {
    slot&.next = ..some(.value = target)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    slots_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = AddressSensitive) * 2)
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            source_slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: AddressSensitive)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference
            destination_slot ::= trusted_mutable_reference_offset#(.t: AddressSensitive)(.base = source_slot, .elements = 1).reference
            cached ::= unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference
            value :: AddressSensitive = (.next = ..none)

            trusted_opaque_move(.destination = source_slot, .source = ~value)
            set_next(.slot = source_slot, .target = cached)
            trusted_opaque_relocate(.source = source_slot, .destination = destination_slot)

            trusted_opaque_drop(.slot = destination_slot)
            deinit(.self = $&slots)
            status_code = 0
        }
    }
}
