consume_and_return := (
    .ffi: $&ForeignFunctionInterface, .deallocator: Virtual<.contract: Deallocator>
) -> (.result: AcquiredStorage) {
    storage ::= unwrap_or_abort(
        .value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = ffi)
    )
    allocation ::= establish_allocation(
        .storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator
    ).allocation
    deinit(.self = $&allocation)
    result = ~storage
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    deallocator :: Virtual<.contract: Deallocator> = to_virtual<.contract: Deallocator>(
        .value = $&allocator
    )
    storage ::= consume_and_return(.ffi = system.ffi, .deallocator = deallocator).result
    allocation ::= establish_allocation(
        .storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator
    ).allocation
    deinit(.self = $&allocation)
}
