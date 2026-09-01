Borrowing : Type = (.reference: $&UInt8)
Container : Type = (.marker: UInt8)

deinit(.self: $&Borrowing) -> () := {}

copy(.value: Borrowing) -> (.result: Borrowing) := {
    result = (.reference = value.reference)
}

store_copy(
    .storage: $&Container,
    .slot: $&Borrowing,
    .source: $&Borrowing,
) -> () := {
    copy ::= source&
    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Container)(
        .storage = storage,
        .destination = slot,
        .source = ~copy,
    )
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    slot_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match slot_result {
                ..error _ { status_code = 2 }
                ..ok ~ slot_payload {
                    slot_storage ::= ~slot_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = slot_storage.data).reference
                    container ::= Container(.marker = 0)
                    source ::= Borrowing(.reference = target.data)
                    store_copy(.storage = $&container, .slot = slot, .source = $&source)
                    trusted_opaque_mark_empty(.storage = $&container)
                    deinit(.self = $&target)
                    deinit(.self = $&slot_storage)
                    status_code = 0
                }
            }
        }
    }
}
