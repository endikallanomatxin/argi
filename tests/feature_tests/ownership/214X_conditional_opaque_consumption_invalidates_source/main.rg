Container : Type = (.marker: UInt8)

store_conditionally(
    .storage: $&Container,
    .slot: $&Allocation,
    .source: $&Allocation,
    .skip: Bool,
) -> () := {
    if skip {
        return
    }
    trusted_opaque_store_owned_in#(.t: Allocation, .storage_type: Container)(
        .storage = storage,
        .destination = slot,
        .source = ~source&,
    )
}

main(.system: System, .skip: Bool = false) -> (.status_code: Int32) := {
    source_result ::= allocate(.self = system.allocator, .size = 1)
    slot_result ::= allocate(.self = system.allocator, .size = size_of(.type = Allocation))
    match source_result {
        ..error _ { status_code = 1 }
        ..ok ~ source_payload {
            source ::= ~source_payload
            match slot_result {
                ..error _ { status_code = 2 }
                ..ok ~ slot_payload {
                    slot_storage ::= ~slot_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = slot_storage.data).reference
                    container ::= Container(.marker = 0)
                    store_conditionally(.storage = $&container, .slot = slot, .source = $&source, .skip = skip)
                    trusted_opaque_release_all(.storage = $&container)
                    if source.size == 1 {
                        status_code = 0
                    }
                }
            }
        }
    }
}
