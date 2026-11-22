Slot := (.reference: &Int32)

make := (.allocator: $&CAllocator) -> (.result: Allocation) {
    local: Int32 = 11
    memory ::= unwrap_or_abort(allocate#(.t: Slot)(.self = allocator, .count = 1))
    raw ::= raw_pointer#(.t: Slot)(.address = memory.data.address).raw
    slot ::= trusted_establish_allocation_slot#(.t: Slot)(
        .allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)
    ).reference
    slot&= Slot(&local)
    result = ~memory
}

main := () -> () {
    assume ffi ::= $&ForeignFunctionInterface()
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= make(.allocator = $&allocator)
}
