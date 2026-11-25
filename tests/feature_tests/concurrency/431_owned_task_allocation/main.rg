forward := (.value: Allocation) -> (.result: Allocation) {
    result = ~value
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    {
        outbound ::= unwrap_or_abort(allocate_shared_c_storage(.self = shared, .size = 1, .alignment = 1, .zeroed = true))
        returning ::= unwrap_or_abort(async_owned#(forward)(.args = (.value = ~outbound), .executor = executor, .ffi = system.ffi))
        match await($&returning) {
            ..ok ~returned {
                pointer ::= trusted_establish_allocation_slot#(.t: UInt8)(
                    .allocation = &returned, .slot = returned.data, .anchor = returned.anchor
                )
                pointer& = 9
                if pointer& != 9 { abort }
            }
            ..error _ { abort }
        }
    }
    recover_ordinary(.owner = $&allocator)
}
