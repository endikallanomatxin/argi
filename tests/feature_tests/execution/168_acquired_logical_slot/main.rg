Empty: Type = ()

main() -> (.status_code: Int32) := {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    allocation ::= allocate_bytes(.self = $&allocator, .size = 16, .alignment = 8)
    match allocation {
        ..error _ { abort }
        ..ok ~memory {
            handle ::= allocation_slot#(.t: UIntNative)(.allocation = &memory, .index = 1).slot
            raw ::= raw_pointer#(.t: UIntNative)(
                .address = uninit_slot_address(.slot = handle)
            ).raw
            index: ?UIntNative = ..some(.value = 1)
            reference ::= trusted_establish_allocation_slot#(.t: UIntNative)(
                .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = index
            ).reference
            reference&= 42
            if reference&!= 42 { abort }
            first ::= allocation_slot#(.t: Empty)(.allocation = &memory, .index = 0).slot
            second ::= allocation_slot#(.t: Empty)(.allocation = &memory, .index = 1).slot
            if uninit_slot_address(.slot = first) != uninit_slot_address(.slot = second) {
                abort
            }
        }
    }
    status_code = 42
}
