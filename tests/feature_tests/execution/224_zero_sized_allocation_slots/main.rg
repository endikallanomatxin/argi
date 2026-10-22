Empty: Type = ()

main() -> (.status_code: Int32) := {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    allocated ::= allocate#(.t: Empty)(.self = $&allocator, .count = 2)
    match allocated {
        ..error _ { abort }
        ..ok ~payload {
            memory ::= ~payload
            first ::= allocation_slot#(.t: Empty)(.allocation = &memory, .index = 0).slot
            second ::= allocation_slot#(.t: Empty)(.allocation = &memory, .index = 1).slot
            if uninit_slot_address(.slot = first) != uninit_slot_address(.slot = second) {
                abort
            }
            raw ::= raw_pointer#(.t: Empty)(.address = uninit_slot_address(.slot = second)).raw
            reference ::= trusted_establish_allocation_slot#(.t: Empty)(
                .allocation = &memory
                .slot       = raw
                .anchor     = memory.anchor
                .index      = ..some(.value = 1)
            ).reference
        }
    }
    status_code = 42
}
