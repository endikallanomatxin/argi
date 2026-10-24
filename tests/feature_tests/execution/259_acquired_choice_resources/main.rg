drops :: Int32 = 0

Resource: Type = (.id: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + self&.id }
)

main() -> (.status_code: Int32) := {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= unwrap_or_abort(.value = allocate#(.t: Choice)(.self = $&allocator, .count = 2))
    raw ::= raw_pointer#(.t: Choice)(.address = memory.data.address).raw
    reference ::= trusted_establish_allocation_slot#(.t: Choice)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    value :: Choice = ..pair(.left = (.id = 7), .right = (.id = 11))
    trusted_opaque_move_in(.storage = $&memory, .destination = reference, .source = ~value)
    second ::= trusted_mutable_reference_offset(.base = reference, .elements = 1).reference
    other :: Choice = ..pair(.left = (.id = 2), .right = (.id = 3))
    trusted_opaque_move_in(.storage = $&memory, .destination = second, .source = ~other)
    match second&{
        ..pair $&payload { deinit(.self = $&payload&.left) }
        ..empty { abort }
    }
    trusted_opaque_drop(.slot = second)
    if drops != 5 { abort }
    match reference&{
        ..pair $&payload {
            deinit(.self = $&payload&.left)
            if payload&.right.id != 11 { abort }
            payload&.left = (.id = 19)
        }
        ..empty { abort }
    }
    trusted_opaque_drop(.slot = reference)
    trusted_opaque_mark_empty(.storage = $&memory)
    status_code = drops
}
