Borrowing : Type = (.reference: $&UInt8)

deinit(.self: $&Borrowing) -> () := {}

store_and_return(.slot: $&Borrowing, .reference: $&UInt8) -> (.result: Bool) := {
    slot&.reference = reference
    result = true
}

release_then_maybe_store(.storage: $&Allocation, .slot: $&Borrowing, .reference: $&UInt8, .condition: Bool) -> () := {
    trusted_opaque_mark_empty(.storage = storage)
    value ::= condition and store_and_return(.slot = slot, .reference = reference).result
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
                    release_then_maybe_store(.storage = $&storage, .slot = slot, .reference = target.data, .condition = false)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
