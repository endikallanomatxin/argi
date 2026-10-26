drops :: Int32 = 0

Resource := (.id: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + self&.id
    }
)

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    allocated ::= allocate<.t: Resource>(.self = $&allocator, .count = 2)
    match allocated {
        ..error _ { abort }
        ..ok ~payload {
            memory ::= ~payload
            raw ::= raw_pointer<.t: Resource>(.address = memory.data.address).raw
            first ::= trusted_establish_allocation_slot<.t: Resource>(
                .allocation = &memory
                .slot       = raw
                .anchor     = memory.anchor
                .index      = ..some(.value = 0)
            ).reference
            second ::= trusted_mutable_reference_offset(.base = first, .elements = 1).reference
            trusted_opaque_move_in(
                .storage = $&memory, .destination = first, .source = Resource(.id = 7)
            )
            trusted_opaque_move_in(
                .storage = $&memory, .destination = second, .source = Resource(.id = 14)
            )
            trusted_opaque_drop(.slot = first)
            again ::= trusted_establish_allocation_slot<.t: Resource>(
                .allocation = &memory
                .slot       = raw
                .anchor     = memory.anchor
                .index      = ..some(.value = 0)
            ).reference
            trusted_opaque_move_in(
                .storage = $&memory, .destination = again, .source = Resource(.id = 21)
            )
            trusted_opaque_drop(.slot = second)
            extracted ::= trusted_opaque_move_out(.storage = $&memory, .slot = again)
            trusted_opaque_mark_empty(.storage = $&memory)
            if drops != 21 { abort }
            deinit(.self = $&extracted)
        }
    }
    status_code = drops
}
