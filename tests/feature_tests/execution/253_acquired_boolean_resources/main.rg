drops :: Int32 = 0

Resource: Type = (.enabled: Bool, .id: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        if self&.enabled { drops = drops + self&.id }
    }
)

main() -> (.status_code: Int32) := {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= unwrap_or_abort(.value = allocate#(.t: Resource)(.self = $&allocator))
    raw ::= raw_pointer#(.t: Resource)(.address = memory.data.address).raw
    reference ::= trusted_establish_allocation_slot#(.t: Resource)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    trusted_opaque_move_in(
        .storage     = $&memory
        .destination = reference
        .source      = Resource(.enabled = true, .id = 42)
    )
    if reference&.enabled == false { abort }
    reference&.enabled = false
    if reference&.enabled { abort }
    reference&.enabled = true
    trusted_opaque_drop(.slot = reference)
    trusted_opaque_mark_empty(.storage = $&memory)
    status_code = drops
}
