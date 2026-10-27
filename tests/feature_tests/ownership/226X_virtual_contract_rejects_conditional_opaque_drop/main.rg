unsafe_allocation := import ("../../_support/unsafe_allocation")

OpaqueStorer#(.Participant: Type): Contract = (
    .store : (.self: $&Participant, .storage: $&Allocation, .slot: $&Tracked, .source: $&Tracked) -> (
    ) where {}
)

Tracked := (.id: Int32)

Keeping := (.marker: UInt8)

Consuming := (.marker: UInt8)

implement OpaqueStorer#(Keeping) (.store = _impl_store_Keeping)

implement OpaqueStorer#(Consuming) (.store = _impl_store_Consuming)

drops :: Int32 = 0

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        drops = drops + 1
    }
)

_impl_store_Keeping := (
    .self: $&Keeping, .storage: $&Allocation, .slot: $&Tracked, .source: $&Tracked
) -> () {}

_impl_store_Consuming := (
    .self: $&Consuming, .storage: $&Allocation, .slot: $&Tracked, .source: $&Tracked
) -> () {
    trusted_opaque_move_in#(.t: Tracked, .storage_type: Allocation) (
        .storage = storage, .destination = slot, .source = ~source&
    )
}

register_keeping := (.value: $&Keeping) -> () {
    _ ::= to_virtual#(.contract: OpaqueStorer)(.value = value)
}

verify := (.status: $&Int32) -> () {
    if drops == 1 {
        status&= 0
    } else {
        status&= 7
    }
}

main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    status_code = 9
    defer verify(.status = $&status_code)
    slot_result ::= allocate_bytes(
        .self = $&allocator_storage, .size = size_of(.type = Tracked)
    )
    match slot_result {
        ..error _ { status_code = 1 }
        ..ok ~slot_payload {
            storage ::= ~slot_payload
            slot ::= trusted_mutable_reinterpret_reference#(.from: UInt8, .to: Tracked)(
                .base = unsafe_allocation.trusted_allocation_byte_rw(
                    .allocation = $&storage, .offset = 0
                ).reference
            ).reference
            keeping ::= Keeping(.marker = 0)
            register_keeping(.value = $&keeping)
            implementation ::= Consuming(.marker = 0)
            virtual ::= to_virtual#(.contract: OpaqueStorer)(.value = $&implementation)
            source :: Tracked = (.id = 1)
            store(.self = $&virtual, .storage = $&storage, .slot = slot, .source = $&source)
            trusted_opaque_drop#(.t: Tracked) (.slot = slot)
            deinit(.self = $&storage)
        }
    }
}
