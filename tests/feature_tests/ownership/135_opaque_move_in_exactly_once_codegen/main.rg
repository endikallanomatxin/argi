unsafe_allocation := import("../../_support/unsafe_allocation")
Tracked : Type = (
    .allocation: Allocation
)

drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    drops = drops + 1
    deinit(.self = $&self&.allocation)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    owned_result ::= allocate(.self = $&allocator_storage, .size = 1)
    slots_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Tracked))
    match owned_result {
        ..error _ { status_code = 1 }
        ..ok ~ owned_payload {
            match slots_result {
                ..error _ { status_code = 2 }
                ..ok ~ slots_payload {
                    slots ::= ~slots_payload
                    slot ::= mutable_reinterpret_reference#(.from: UInt8, .to: Tracked)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&slots, .offset = 0).reference).reference
                    value :: Tracked = (.allocation = ~owned_payload)
                    trusted_opaque_move_in#(.t: Tracked, .storage_type: Allocation)(
                        .storage = $&slots,
                        .destination = slot,
                        .source = ~value,
                    )

                    if drops != 0 {
                        status_code = 3
                        return
                    }
                    trusted_opaque_drop(.slot = slot)
                    deinit(.self = $&slots)
                    if drops == 1 {
                        status_code = 0
                    } else {
                        status_code = 4
                    }
                }
            }
        }
    }
}
