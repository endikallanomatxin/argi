Router : Type = (
    .allocation: Allocation
    .route: $&Int32
)

deinit(.self: $&Router) -> () := {
    deinit(.self = $&self&.allocation)
}

store_pair(
    .first_slot: $&Allocation,
    .first: Allocation,
    .second_slot: $&Router,
    .second: Router,
) -> () := {
    trusted_opaque_move#(.t: Allocation)(.destination = first_slot, .source = ~first)
    trusted_opaque_move#(.t: Router)(.destination = second_slot, .source = ~second)
}

main(.system: System) -> (.status_code: Int32) := {
    route :: Int32 = 7
    first_result ::= allocate(.self = system.allocator, .size = 1)
    second_result ::= allocate(.self = system.allocator, .size = 1)
    slots_result ::= allocate(
        .self = system.allocator,
        .size = size_of(.type = Allocation) + size_of(.type = Router),
    )

    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            first ::= ~first_payload
            match second_result {
                ..error _ { status_code = 2 }
                ..ok ~ second_payload {
                    second ::= Router(
                        .allocation = ~second_payload,
                        .route = $&route,
                    )
                    match slots_result {
                        ..error _ { status_code = 3 }
                        ..ok ~ slots_payload {
                            slots ::= ~slots_payload
                            first_slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Allocation)(.base = slots.data).reference
                            second_address ::= cast#(.to: UIntNative)(.value = slots.data) + size_of(.type = Allocation)
                            second_raw ::= raw_pointer#(.t: Router)(.address = second_address)
                            second_slot ::= establish_inherited_reference#(.t: Router)(
                                .raw = second_raw,
                                .root = cast#(.to: &Any)(.value = slots.data),
                            ).reference

                            store_pair(
                                .first_slot = first_slot,
                                .first = ~first,
                                .second_slot = second_slot,
                                .second = ~second,
                            )

                            status_code = 0
                        }
                    }
                }
            }
        }
    }
}
