Borrowing : Type = (
    .reference: $&UInt8
)

deinit(.self: $&Borrowing) -> () := {
}

release_inner(.storage: $&Allocation) -> () := {
    trusted_opaque_release_all(.storage = storage)
}

release_outer(.storage: $&Allocation) -> () := {
    release_inner(.storage = storage)
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
                    trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&storage, .destination = slot, .source = ~value)
                    trusted_opaque_drop_owned(.slot = slot)
                    release_outer(.storage = $&storage)
                    deinit(.self = $&target)
                    deinit(.self = $&storage)
                    status_code = 0
                }
            }
        }
    }
}
