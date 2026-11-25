replace_address := (.slot: $&UIntNative) -> () { slot& = 0 }

return_owner := (.value: Allocation) -> (.result: Allocation) { result = ~value }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    allocation :: Allocation = unwrap_or_abort(allocate_shared_c_storage(.self = shared, .size = 1, .alignment = 1, .zeroed = true))
    replace_address(.slot = $&allocation.data.address)
    task ::= unwrap_or_abort(async_owned#(return_owner)(.args = (.value = ~allocation), .executor = executor, .ffi = system.ffi))
    match await($&task) {
        ..ok ~returned {}
        ..error _ { abort }
    }
    recover_ordinary(.owner = $&allocator)
}
