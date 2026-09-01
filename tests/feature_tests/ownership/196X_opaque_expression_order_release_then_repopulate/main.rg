Borrowing : Type = (.reference: $&UInt8)

deinit(.self: $&Borrowing) -> () := {}

release_and_return(.storage: $&Allocation) -> (.result: UInt8) := {
    trusted_opaque_mark_empty(.storage = storage)
    result = 0
}

store_and_return(.slot: $&Borrowing, .reference: $&UInt8) -> (.result: UInt8) := {
    slot&.reference = reference
    result = 0
}

consume(.left: UInt8, .right: UInt8) -> (.result: UInt8) := { result = left + right }

release_then_store(.storage: $&Allocation, .slot: $&Borrowing, .reference: $&UInt8) -> () := {
    value ::= consume(
        .left = release_and_return(.storage = storage).result,
        .right = store_and_return(.slot = slot, .reference = reference).result,
    ).result
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    storage_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match storage_result {
                ..error _ { status_code = 2 }
                ..ok ~ storage_payload {
                    storage ::= ~storage_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = storage.data).reference
                    initial :: Borrowing = (.reference = target.data)
                    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&storage, .destination = slot, .source = ~initial)
                    trusted_opaque_drop(.slot = slot)
                    release_then_store(.storage = $&storage, .slot = slot, .reference = target.data)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
