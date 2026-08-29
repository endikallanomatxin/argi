Borrowing : Type = (.reference: $&UInt8)

deinit(.self: $&Borrowing) -> () := {}

release_and_return(.storage: $&Allocation) -> (.result: Bool) := {
    trusted_opaque_release_all(.storage = storage)
    result = true
}

maybe_release(.storage: $&Allocation, .condition: Bool) -> () := {
    value ::= condition and release_and_return(.storage = storage).result
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
                    trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&storage, .destination = slot, .source = ~initial)
                    trusted_opaque_drop_owned(.slot = slot)
                    maybe_release(.storage = $&storage, .condition = false)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
