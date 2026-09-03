Borrowing : Type = (
    .reference: $&UInt8
)

deinit(.self: $&Borrowing) -> () := {
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
                    value :: Borrowing = (.reference = target.data)
                    trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&storage, .destination = slot, .source = ~value)

                    -- The last opaque slot is gone, but without a domain-wide
                    -- discharge the conservative domain fact still blocks this.
                    trusted_opaque_drop(.slot = slot)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
