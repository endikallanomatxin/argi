unsafe_allocation := import("../../_support/unsafe_allocation")
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
    trusted_opaque_move_in#(.t: Allocation, .storage_type: Container)(
        .storage = storage,
        .destination = slot,
        .source = ~source&,
    )
}

main(.system: System, .skip: Bool = false) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    source_result ::= allocate(.self = $&allocator_storage, .size = 1)
    slot_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Allocation))
    match source_result {
        ..error _ { status_code = 1 }
        ..ok ~ source_payload {
            source ::= ~source_payload
            match slot_result {
                ..error _ { status_code = 2 }
                ..ok ~ slot_payload {
                    slot_storage ::= ~slot_payload
                    slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slot_storage, .offset = 0).reference).reference
                    container ::= Container(.marker = 0)
                    store_conditionally(.storage = $&container, .slot = slot, .source = $&source, .skip = skip)
                    trusted_opaque_mark_empty(.storage = $&container)
                    if source.size == 1 {
                        status_code = 0
                    }
                }
            }
        }
    }
}
