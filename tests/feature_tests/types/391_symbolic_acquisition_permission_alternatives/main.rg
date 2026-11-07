Acquire#(.T: Type): Contract = (
    .acquire: (.self: &T) -> (.result: AcquiredStorage) where owns(result)
)
Provider := (.ffi: $&ForeignFunctionInterface)
implement Acquire#(Provider) (
    .acquire = (.self: &Provider) -> (.result: AcquiredStorage) {
        result = unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = self&.ffi))
    }
)
choose := (.flag: Bool, .first: AcquiredStorage, .second: AcquiredStorage) -> (.result: AcquiredStorage) {
    if flag { result = ~first } else { result = ~second }
}
main := (.system: System) -> () {
    provider ::= Provider(system.ffi)
    factory ::= to_virtual#(Acquire)(&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= to_virtual#(Deallocator)($&allocator)
    first ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    second ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 16, .alignment = 8, .ffi = system.ffi))
    -- AcquiredStorage carries establishment permission, not cleanup. The
    -- false branch selects second; release the unselected first acquisition.
    first_address ::= acquired_storage_address(.storage = &first)
    acquired ::= choose(.flag = false, .first = ~first, .second = ~second)
    allocation ::= establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
    aligned_free(.address = first_address, .ffi = system.ffi)
}
