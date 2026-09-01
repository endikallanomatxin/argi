SelfRef : Type = (
    .value: Int32
    .reference: &Int32
)

main(.system: System) -> (.status_code: Int32) := {
    seed :: Int32 = 0
    value :: SelfRef = (.value = 7, .reference = &seed)
    value.reference = &value.value

    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = SelfRef))
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: SelfRef)(.base = slots.data).reference
            -- The reference depends on `value`'s structural storage. Opaque
            -- ownership rejects it rather than allowing a later physical move
            -- to leave the representation address-sensitive.
            trusted_opaque_store(.destination = slot, .source = ~value)
            deinit(.self = $&slots)
            status_code = 0
        }
    }
}
