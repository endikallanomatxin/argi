Borrowing : Type = (
    .reference: $&UInt8
)

deinit(.self: $&Borrowing) -> () := {
}

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    first_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    second_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match first_result {
                ..error _ { status_code = 2 }
                ..ok ~ first_payload {
                    first ::= ~first_payload
                    match second_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ second_payload {
                            second ::= ~second_payload
                            first_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = first.data).reference
                            second_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = second.data).reference
                            first_value :: Borrowing = (.reference = target.data)
                            second_value :: Borrowing = (.reference = target.data)
                            trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&first, .destination = first_slot, .source = ~first_value)
                            trusted_opaque_store_owned_in#(.t: Borrowing, .storage_type: Allocation)(.storage = $&second, .destination = second_slot, .source = ~second_value)
                            trusted_opaque_drop_owned(.slot = first_slot)
                            trusted_opaque_drop_owned(.slot = second_slot)
                            trusted_opaque_release_all(.storage = $&first)
                            trusted_opaque_release_all(.storage = $&second)
                            deinit(.self = $&target)
                            deinit(.self = $&first)
                            deinit(.self = $&second)
                            status_code = 0
                        }
                    }
                }
            }
        }
    }
}
