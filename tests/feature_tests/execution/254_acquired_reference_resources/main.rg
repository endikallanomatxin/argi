drops :: Int32 = 0

Resource := (.source: &Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + self&.source&
    }
)

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()

    value :: Int32 = 42
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= unwrap_or_abort(.value = allocate#(.t: Resource)(.self = $&allocator))
    raw ::= raw_pointer#(.t: Resource)(.address = memory.data.address).raw
    reference ::= trusted_establish_allocation_slot#(.t: Resource)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    trusted_opaque_move_in(
        .storage = $&memory, .destination = reference, .source = Resource(.source = &value)
    )
    borrowed ::= reference&.source
    if borrowed&!= 42 { abort }
    trusted_opaque_drop(.slot = reference)
    trusted_opaque_mark_empty(.storage = $&memory)
    status_code = drops
}
