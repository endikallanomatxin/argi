TrackedBorrowing : Type = (
    .id: Int32
    .reference: &UInt8
)

external :: UInt8 = 9
drops :: Int32 = 0

deinit(.self: $&TrackedBorrowing) -> () := {
    drops = drops + 1
}

store_local(
    .storage: $&Allocation,
    .slot: $&TrackedBorrowing,
    .target: &UInt8,
) -> () := {
    local :: TrackedBorrowing = (
        .id = 1,
        .reference = target,
    )
    trusted_opaque_store_owned_in#(.t: TrackedBorrowing, .storage_type: Allocation)(
        .storage = storage,
        .destination = slot,
        .source = ~local,
    )
}

main(.system: System) -> (.status_code: Int32) := {
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = TrackedBorrowing))
    match slots_result {
        ..error _ { status_code = 1 }
        ..ok ~ slots_payload {
            slots ::= ~slots_payload
            slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: TrackedBorrowing)(.base = slots.data).reference
            store_local(
                .storage = $&slots,
                .slot = slot,
                .target = &external,
            )
            trusted_opaque_drop_owned(.slot = slot)
            deinit(.self = $&slots)
            if drops == 1 {
                status_code = 0
            } else {
                status_code = 3
            }
        }
    }
}
