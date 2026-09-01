Borrowing : Type = (
    .reference: $&UInt8
)

external :: UInt8 = 7

deinit(.self: $&Borrowing) -> () := {
}

copy(.value: Borrowing) -> (.result: Borrowing) := {
    result = (.reference = value.reference)
}

main(.system: System) -> (.status_code: Int32) := {
    allocation_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match allocation_result {
        ..error _ { status_code = 1 }
        ..ok ~ allocation_payload {
            storage ::= ~allocation_payload
            slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = storage.data).reference
            value :: Borrowing = (.reference = $&external)
            trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
                .storage = $&storage,
                .destination = slot,
                .source = ~value,
            )
            extracted ::= slot&

            trusted_opaque_drop(.slot = slot)
            deinit(.self = $&storage)

            observed ::= extracted.reference&
            if observed == 7 {
                status_code = 0
            } else {
                status_code = 2
            }
        }
    }
}
