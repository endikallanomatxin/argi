inspect := (.storage: &AcquiredStorage) -> (.address: UIntNative) {
    address = acquired_storage_address(.storage = storage).address
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    deallocator :: Virtual#(.contract: Deallocator) = to_virtual#(.contract: Deallocator)(
        .value = $&allocator
    )
    storage ::= unwrap_or_abort(
        .value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi)
    )
    address ::= inspect(.storage = &storage).address
    allocation ::= establish_allocation(
        .storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator
    ).allocation
    marker :: UInt8 = 0
    root ::= erase_reference#(.t: UInt8)(.base = &marker).reference
    raw ::= trusted_establish_inherited_storage(.address = address, .root = root).raw
    abort
}
