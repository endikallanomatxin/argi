AddressSensitive : Type = (
    .value: UInt8
    .reference: Nullable#(.t: $&UInt8)
)

deinit(.self: $&AddressSensitive) -> () := {
}

main(.system: System) -> (.status_code: Int32) := {
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = AddressSensitive) * 2)
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            source_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: AddressSensitive)(.base = slots.data).reference
            destination_slot ::= mutable_reference_offset#(.t: AddressSensitive)(.base = source_slot, .elements = 1).reference
            value :: AddressSensitive = (.value = 7, .reference = ..none)

            -- The value has no reference dependency when it crosses the
            -- current opaque-store boundary, so the store accepts it.
            trusted_opaque_store_owned(.destination = source_slot, .source = ~value)

            -- Introduce address sensitivity only after storage became opaque.
            -- The checker does not attach this write to opaque provenance, and
            -- relocation is an unconditional checker no-op, so this unsafe
            -- representation move currently passes.
            source_slot&.reference = ..some(.value = $&source_slot&.value)
            trusted_opaque_relocate_owned(.source = source_slot, .destination = destination_slot)

            trusted_opaque_drop_owned(.slot = destination_slot)
            deinit(.self = $&slots)
            status_code = 0
        }
    }
}
