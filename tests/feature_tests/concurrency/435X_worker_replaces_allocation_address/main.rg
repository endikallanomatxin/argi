replace_address := (.slot: $&UIntNative) -> (.tag: UInt8) {
    slot& = 0
    tag = 1
}

forward := (.tag: UInt8, .allocation: Allocation) -> (.result: Allocation) {
    result = ~allocation
}

set_first_byte := (.allocation: &Allocation, .byte: UInt8) -> () {
    pointer ::= trusted_establish_allocation_slot#(UInt8)(
        .allocation = allocation, .slot = allocation&.data, .anchor = allocation&.anchor
    )
    pointer& = byte
}

mutate := (.value: Allocation) -> (.result: Allocation) {
    owned :: Allocation = ~value
    set_first_byte(.allocation = &owned, .byte = 8)
    result = forward(.tag = replace_address(.slot = $&owned.data.address), .allocation = ~owned)
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    {
        outbound ::= unwrap_or_abort(allocate_shared_c_storage(.self = shared, .size = 1, .alignment = 1, .zeroed = true))
        returning ::= unwrap_or_abort(async_owned#(mutate)(.args = (.value = ~outbound), .executor = executor, .ffi = system.ffi))
        match await($&returning) {
            ..ok ~returned {}
            ..error _ { abort }
        }
    }
    recover_ordinary(.owner = $&allocator)
}
