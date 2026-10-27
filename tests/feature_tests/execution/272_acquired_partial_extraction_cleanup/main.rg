drops :: Int32 = 0

Resource := (.id: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () { drops = drops + self&.id })

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    {
        memory ::= unwrap_or_abort(.value = allocate#(.t: Choice)(.self = $&allocator))
        raw ::= raw_pointer#(.t: Choice)(.address = memory.data.address).raw
        slot ::= trusted_establish_allocation_slot#(.t: Choice)(
            .allocation = &memory
            .slot       = raw
            .anchor     = memory.anchor
            .index      = ..some(.value = 0)
        ).reference
        value :: Choice = ..pair(.left = (.id = 7), .right = (.id = 11))
        trusted_opaque_move_in(.storage = $&memory, .destination = slot, .source = ~value)
        match slot&{
            ..pair $&payload {
                extracted ::= trusted_opaque_move_out(
                    .storage = $&memory, .slot = $&payload&.left
                )
                if extracted.id != 7 { abort }
            }
            ..empty { abort }
        }
        if drops != 7 { abort }
        trusted_opaque_drop(.slot = slot)
        trusted_opaque_mark_empty(.storage = $&memory)
    }
    if drops != 18 { abort }
    {
        memory ::= unwrap_or_abort(.value = allocate#(.t: [2]Resource)(.self = $&allocator))
        raw ::= raw_pointer#(.t: [2]Resource)(.address = memory.data.address).raw
        slot ::= trusted_establish_allocation_slot#(.t: [2]Resource)(
            .allocation = &memory
            .slot       = raw
            .anchor     = memory.anchor
            .index      = ..some(.value = 0)
        ).reference
        values :: [2]Resource = ((.id = 11), (.id = 13))
        trusted_opaque_move_in(.storage = $&memory, .destination = slot, .source = ~values)
        {
            extracted ::= trusted_opaque_move_out(.storage = $&memory, .slot = $&slot&[0])
            if extracted.id != 11 { abort }
        }
        if drops != 29 { abort }
        trusted_opaque_drop(.slot = slot)
        trusted_opaque_mark_empty(.storage = $&memory)
    }
    status_code = drops
}
