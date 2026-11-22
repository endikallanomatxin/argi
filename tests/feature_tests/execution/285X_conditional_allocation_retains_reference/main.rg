Slot := (.reference: &Int32)

put := (.memory: $&Allocation, .value: &Int32) -> () {
    raw ::= raw_pointer#(.t: Slot)(.address = memory&.data.address).raw
    slot ::= trusted_establish_allocation_slot#(.t: Slot)(
        .allocation = memory, .slot = raw, .anchor = memory&.anchor, .index = ..some(.value = 0)
    ).reference
    entry ::= Slot(value)
    trusted_opaque_move_in#(Slot, Allocation)(memory, slot, ~entry)
}

make := (.allocator: $&CAllocator, .choose: Bool) -> (.result: Allocation) {
    local: Int32 = 11
    memory ::= unwrap_or_abort(allocate#(.t: Slot)(.self = allocator, .count = 1))
    other ::= unwrap_or_abort(allocate#(.t: Slot)(.self = allocator, .count = 1))
    selected ::= $&memory
    if choose { selected = $&other }
    put(.memory = selected, .value = &local)
    result = ~other
}

main := () -> () {
    assume ffi ::= $&ForeignFunctionInterface()
    allocator ::= CAllocator(.ffi = ffi)
    memory ::= make(.allocator = $&allocator, .choose = true)
}
