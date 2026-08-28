Borrowing : Type = (
    .reference: $&UInt8
)

external :: UInt8 = 7

deinit(.self: $&Borrowing) -> () := {
}

extract(.slot: $&Borrowing) -> (.result: $&UInt8) := {
    result = slot&.reference
}

main(.system: System) -> (.status_code: Int32) := {
    first_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            storage ::= ~first_payload
            first_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = storage.data).reference
            first_value :: Borrowing = (.reference = $&external)
            trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(
                .storage = $&storage,
                .destination = first_slot,
                .source = ~first_value,
            )
            trusted_opaque_drop_owned(.slot = first_slot)
            deinit(.self = $&storage)

            second_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second_payload {
                    storage = ~second_payload
                    second_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = storage.data).reference
                    second_value :: Borrowing = (.reference = $&external)
                    trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(
                        .storage = $&storage,
                        .destination = second_slot,
                        .source = ~second_value,
                    )
                    fresh ::= extract(.slot = second_slot).result
                    observed ::= fresh&
                    if observed == 7 {
                        status_code = 0
                    } else {
                        status_code = 3
                    }
                    trusted_opaque_drop_owned(.slot = second_slot)
                    deinit(.self = $&storage)
                }
            }
        }
    }
}
