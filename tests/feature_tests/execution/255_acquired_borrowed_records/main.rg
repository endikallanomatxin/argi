Pair := (.links: [2]&Int32, .tag: UInt8)

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()

    left :: Int32 = 11
    right :: Int32 = 31
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= unwrap_or_abort(.value = allocate#(.t: Pair)(.self = $&allocator, .count = 2))
    raw ::= raw_pointer#(.t: Pair)(.address = memory.data.address).raw
    first ::= trusted_establish_allocation_slot#(.t: Pair)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    second ::= trusted_mutable_reference_offset(.base = first, .elements = 1).reference
    first&= Pair(.links = (&left, &right), .tag = 1)
    second&= Pair(.links = (&right, &left), .tag = 2)
    first&.tag = 3
    a ::= first&.links[0]
    b ::= second&.links[0]
    if first&.tag != 3 or second&.tag != 2 { abort }
    status_code = a&+ b&
}
