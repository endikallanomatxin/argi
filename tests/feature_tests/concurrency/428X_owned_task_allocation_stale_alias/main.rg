return_owner := (.value: Allocation) -> (.result: Allocation) { result = ~value }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    allocation ::= unwrap_or_abort(allocate_shared_c_storage(.self = shared, .size = 1, .alignment = 1, .zeroed = true))
    pointer ::= trusted_establish_allocation_slot#(.t: UInt8)(
        .allocation = &allocation, .slot = allocation.data, .anchor = allocation.anchor
    )
    task ::= unwrap_or_abort(async_owned#(return_owner)(.args = (.value = ~allocation), .executor = executor, .ffi = system.ffi))
    match await($&task) {
        ..ok ~returned { pointer& = 7 }
        ..error _ { abort }
    }
    recover_ordinary(.owner = $&allocator)
}
