Borrowing : Type = (
    .reference: $&UInt8
)

external :: UInt8 = 7

deinit(.self: $&Borrowing) -> () := {
}

extract_inner(.slot: $&Borrowing) -> (.result: $&UInt8) := {
    result = slot&.reference
}

extract_outer(.slot: $&Borrowing) -> (.result: $&UInt8) := {
    result = extract_inner(.slot = slot).result
}

main(.system: System) -> (.status_code: Int32) := {
    domain_result ::= allocate(.self = system.allocator, .size = 1)
    match domain_result {
        ..error _ { status_code = 1 }
        ..ok ~ domain_payload {
            domain ::= ~domain_payload
            backing_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
            match backing_result {
                ..error _ {
                    deinit(.self = $&domain)
                    status_code = 2
                }
                ..ok ~ backing_payload {
                    backing ::= ~backing_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = backing.data).reference
                    value :: Borrowing = (.reference = $&external)
                    trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(
                        .storage = $&domain,
                        .destination = slot,
                        .source = ~value,
                    )
                    extracted ::= extract_outer(.slot = slot).result

                    trusted_opaque_drop_owned(.slot = slot)
                    deinit(.self = $&domain)

                    observed ::= extracted&
                    if observed == 7 {
                        status_code = 0
                    } else {
                        status_code = 3
                    }
                    deinit(.self = $&backing)
                }
            }
        }
    }
}
