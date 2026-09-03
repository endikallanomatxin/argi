Borrowing : Type = (
    .reference: $&UInt8
)

main(.system: System) -> (.status_code: Int32) := {
    target_result ::= allocate(.self = system.allocator, .size = 1)
    slots_result ::= allocate(.self = system.allocator, .size = size_of(.type = Borrowing))
    match target_result {
        ..error _ { status_code = 1 }
        ..ok ~ target_payload {
            target ::= ~target_payload
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    if slots.size > 0 {
                        slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Borrowing)(.base = slots.data).reference
                        hidden :: Borrowing = (.reference = target.data)
                        trusted_opaque_move_in#(.t: Borrowing, .storage_type: Allocation)(
                            .storage = $&slots,
                            .destination = slot,
                            .source = ~hidden,
                        )
                    }

                    -- The join must retain the dependency from the branch that
                    -- populated opaque storage.
                    deinit(.self = $&target)
                    status_code = 0
                }
            }
        }
    }
}
