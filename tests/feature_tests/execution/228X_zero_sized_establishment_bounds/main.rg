Empty: Type = ()

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    allocated ::= allocate#(.t: Empty)(.self = $&allocator, .count = 2)
    match allocated {
        ..error _ { abort }
        ..ok ~payload {
            memory ::= ~payload
            raw ::= raw_pointer#(.t: Empty)(.address = memory.data.address).raw
            reference ::= trusted_establish_allocation_slot#(.t: Empty)(
                .allocation = &memory
                .slot       = raw
                .anchor     = memory.anchor
                .index      = ..some(.value = 2)
            ).reference
        }
    }
    status_code = 42
}
