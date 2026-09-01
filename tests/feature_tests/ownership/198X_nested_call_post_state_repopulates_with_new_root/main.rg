Borrowing : Type = (
    .reference: $&UInt8
)

old_root :: UInt8 = 7

deinit(.self: $&Borrowing) -> () := {}

store_and_return(.slot: $&Borrowing, .reference: $&UInt8) -> (.result: UInt8) := {
    slot&.reference = reference
    result = 0
}

reset_and_store(.storage: $&Allocation, .slot: $&Borrowing, .reference: $&UInt8) -> () := {
    trusted_opaque_mark_empty(.storage = storage)
    value ::= store_and_return(.slot = slot, .reference = reference).result
}

main(.system: System) -> (.status_code: Int32) := {
    new_root_result ::= allocate(.self = system.allocator, .size = 1)
    storage_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match new_root_result {
        ..error _ { status_code = 1 }
        ..ok ~ new_root_payload {
            new_root ::= ~new_root_payload
            match storage_result {
                ..error _ { status_code = 2 }
                ..ok ~ storage_payload {
                    storage ::= ~storage_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = storage.data).reference
                    initial :: Borrowing = (.reference = $&old_root)
                    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&storage, .destination = slot, .source = ~initial)
                    trusted_opaque_drop(.slot = slot)
                    reset_and_store(.storage = $&storage, .slot = slot, .reference = new_root.data)
                    deinit(.self = $&new_root)
                    status_code = 0
                }
            }
        }
    }
}
