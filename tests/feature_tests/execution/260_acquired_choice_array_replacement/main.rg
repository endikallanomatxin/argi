drops :: Int32 = 0

Resource := (.id: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () { drops = drops + self&.id }
)

replacement := (.selection: $&UIntNative) -> (.value: Choice) {
    selection&= 1
    value = ..empty
}

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()

    allocator ::= CAllocator(.ffi = ffi)
    memory ::= unwrap_or_abort(.value = allocate#(.t: [2]Choice)(.self = $&allocator))
    raw ::= raw_pointer#(.t: [2]Choice)(.address = memory.data.address).raw
    slot ::= trusted_establish_allocation_slot#(.t: [2]Choice)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    values :: [2]Choice = (
        ..pair(.left = (.id = 7), .right = (.id = 11)),
        ..pair(.left = (.id = 11), .right = (.id = 13))
    )
    trusted_opaque_move_in(.storage = $&memory, .destination = slot, .source = ~values)
    selection :: UIntNative = 0
    slot&[selection] = replacement(.selection = $&selection)
    if selection != 1 or drops != 18 { abort }
    match slot&[1] {
        ..pair&payload { if payload&.right.id != 13 { abort } }
        ..empty { abort }
    }
    trusted_opaque_drop(.slot = slot)
    trusted_opaque_mark_empty(.storage = $&memory)
    status_code = drops
}
