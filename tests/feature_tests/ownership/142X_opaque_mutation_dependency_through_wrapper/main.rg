AddressSensitive : Type = (
    .reference: Nullable#(.t: $&UInt8)
)

deinit(.self: $&AddressSensitive) -> () := {
}

set_reference(.slot: $&AddressSensitive, .target: $&UInt8) -> () := {
    slot&.reference = ..some(.value = target)
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = AddressSensitive))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: AddressSensitive)(.base = slots.data).reference
                    value :: AddressSensitive = (.reference = ..none)
                    trusted_opaque_store_owned_in#(.t: AddressSensitive, .storage_type: Allocation)(
                        .storage = $&slots,
                        .destination = slot,
                        .source = ~value,
                    )

                    set_reference(.slot = slot, .target = target.data)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
