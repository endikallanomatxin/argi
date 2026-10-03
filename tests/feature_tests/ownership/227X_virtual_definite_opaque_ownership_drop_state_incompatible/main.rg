unsafe_allocation := import("../../_support/unsafe_allocation")
OpaqueStorer : Abstract = (
    store(.self: $&Self, .storage: $&Allocation, .slot: $&Tracked, .source: $&Tracked) -> ()
)

Tracked : Type = (.id: Int32)
First : Type = (.marker: UInt8)
Second : Type = (.marker: UInt8)
First implements OpaqueStorer
Second implements OpaqueStorer

drops :: Int32 = 0

Tracked deinit(.self: $&Tracked) -> () := {
    drops = drops + 1
}

store(.self: $&First, .storage: $&Allocation, .slot: $&Tracked, .source: $&Tracked) -> () := {
    trusted_opaque_move_in#(.t: Tracked, .storage_type: Allocation)(
        .storage = storage,
        .destination = slot,
        .source = ~source&,
    )
}

store(.self: $&Second, .storage: $&Allocation, .slot: $&Tracked, .source: $&Tracked) -> () := {
    trusted_opaque_move_in#(.t: Tracked, .storage_type: Allocation)(
        .storage = storage,
        .destination = slot,
        .source = ~source&,
    )
}

register_second(.value: $&Second) -> () := {
    _ ::= to_virtual#(.abstract: OpaqueStorer)(.value = value)
}

verify(.status: $&Int32) -> () := {
    if drops == 1 {
        status& = 0
    } else {
        status& = 7
    }
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    status_code = 9
    #defer verify(.status = $&status_code)
    slot_result ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Tracked))
    match slot_result {
        ..error _ { status_code = 1 }
        ..ok ~ slot_payload {
            storage ::= ~slot_payload
            slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Tracked)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&storage, .offset = 0).reference).reference
            second ::= Second(.marker = 0)
            register_second(.value = $&second)
            implementation ::= First(.marker = 0)
            virtual ::= to_virtual#(.abstract: OpaqueStorer)(.value = $&implementation)
            source :: Tracked = (.id = 1)
            store(.self = $&virtual, .storage = $&storage, .slot = slot, .source = $&source)
            trusted_opaque_drop#(.t: Tracked)(.slot = slot)
            deinit(.self = $&storage)
        }
    }
}
