AddressSensitive : Type = (
    .reference: Nullable#(.t: &UInt8)
)

external :: UInt8 = 9

deinit(.self: $&AddressSensitive) -> () := {
}

main(.system: System) -> (.status_code: Int32) := {
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = AddressSensitive))
    unrelated_result ::= allocate(.self = system.allocator, .size = 1)
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            match unrelated_result {
                ..error _ { status_code = 2 }
                ..ok ~ unrelated_payload {
                    unrelated ::= ~unrelated_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: AddressSensitive)(.base = slots.data).reference
                    value :: AddressSensitive = (.reference = ..none)
                    trusted_opaque_move_in#(.t: AddressSensitive, .storage_type: Allocation)(
                        .storage = $&slots,
                        .destination = slot,
                        .source = ~value,
                    )

                    slot&.reference = ..some(.value = &external)
                    deinit(.self = $&unrelated)
                    trusted_opaque_drop(.slot = slot)
                    deinit(.self = $&slots)
                    status_code = 0
                }
            }
        }
    }
}
