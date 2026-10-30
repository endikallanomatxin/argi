main := () -> () {
    assume ffi ::= $&ForeignFunctionInterface()

    allocator ::= CAllocator(.ffi = ffi)
    allocation ::= allocate_bytes(.self = $&allocator, .size = 32, .alignment = 8)
    match allocation {
        ..error _ { abort }
        ..ok ~memory {
            raw ::= raw_pointer#(.t: UIntNative)(.address = memory.data.address + 8).raw
            index: ?UIntNative = ..some(.value = 2)
            reference ::= trusted_establish_allocation_slot#(.t: UIntNative)(
                .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = index
            ).reference
        }
    }
}
