unsafe_allocation := import("../../_support/unsafe_allocation")
Borrowing : Type = (.reference: $&UInt8)
Container : Type = (.marker: UInt8)

deinit(.self: $&Borrowing) -> () := {}

copy(.self: &Borrowing) -> (.value: Borrowing) := {
    value = (.reference = self&.reference)
}

Borrowing implements InfalliblyCopyable

store_copy(
    .storage: $&Container,
    .slot: $&Borrowing,
    .source: $&Borrowing,
) -> () := {
    copy ::= copy(.self = source)
    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Container)(
        .storage = storage,
        .destination = slot,
        .source = ~copy,
    )
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    target_result ::= allocate(.self = $&allocator_storage, .size = 1)
    slot_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match slot_result {
                ..error _ { status_code = 2 }
                ..ok ~ slot_payload {
                    slot_storage ::= ~slot_payload
                    slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slot_storage, .offset = 0).reference).reference
                    container ::= Container(.marker = 0)
                    source ::= Borrowing(.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&target, .offset = 0).reference)
                    store_copy(.storage = $&container, .slot = slot, .source = $&source)
                    deinit(.self = $&target)
                    trusted_opaque_mark_empty(.storage = $&container)
                    deinit(.self = $&slot_storage)
                    status_code = 0
                }
            }
        }
    }
}
