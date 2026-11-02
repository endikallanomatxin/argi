main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()

    allocator ::= CAllocator(.ffi = ffi)
    allocated ::= allocate#(.t: Int32)(.self = $&allocator, .count = 2)
    match allocated {
        ..error _ { abort }
        ..ok ~payload {
            memory ::= ~payload
            memory.size = 4
            raw ::= raw_pointer#(.t: Int32)(.address = memory.data.address).raw
            first ::= trusted_establish_allocation_slot#(.t: Int32)(
                .allocation = &memory
                .slot       = raw
                .anchor     = memory.anchor
                .index      = ..some(.value = 0)
            ).reference
            second ::= trusted_mutable_reference_offset(.base = first, .elements = 1).reference
            second&= 42
            status_code = second&
        }
    }
}
