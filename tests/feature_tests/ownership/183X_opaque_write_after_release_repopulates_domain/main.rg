Borrowing : Type = (
    .reference: $&UInt8
)

external :: UInt8 = 7

deinit(.self: $&Borrowing) -> () := {
}

reset_and_store(
    .storage: $&Allocation,
    .slot: $&Borrowing,
    .reference: $&UInt8,
) -> () := {
    trusted_opaque_release_all(.storage = storage)
    slot&.reference = reference
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
                    initial :: Borrowing = (.reference = $&external)
                    trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&storage, .destination = slot, .source = ~initial)
                    trusted_opaque_drop_owned(.slot = slot)

                    reset_and_store(.storage = $&storage, .slot = slot, .reference = target.data)
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
