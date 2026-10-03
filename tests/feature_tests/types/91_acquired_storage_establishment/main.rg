forward(.storage: AcquiredStorage) -> (.result: AcquiredStorage) := { result = ~storage }

establish(.storage: AcquiredStorage, .size: UIntNative, .deallocator: Virtual#(.abstract: Deallocator)) -> (.result: Allocation) := {
    result = establish_allocation(.storage = ~storage, .size = size, .alignment = 8, .deallocator = deallocator).allocation
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&allocator)
    storage ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 32, .alignment = 8, .ffi = system.ffi))
    alias ::= forward(.storage = ~storage).result
    allocation ::= establish(.storage = ~alias, .size = 24, .deallocator = deallocator).result
    raw ::= raw_pointer#(.t: UIntNative)(.address = allocation.data.address + 16).raw
    slot ::= trusted_establish_allocation_slot#(.t: UIntNative)(.allocation = &allocation, .slot = raw, .anchor = allocation.anchor).reference
    slot& = 123
    if slot& != 123 { status_code = 1 }
    deinit(.self = $&allocation)
    empty ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 0, .alignment = 8, .ffi = system.ffi))
    empty_allocation ::= establish(.storage = ~empty, .size = 0, .deallocator = deallocator).result
    deinit(.self = $&empty_allocation)
    pages ::= unwrap_or_abort(.value = acquire_page_storage(.memory = system.memory, .size = 32, .alignment = 8192))
    page_deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = system.memory)
    page_allocation ::= establish_allocation(.storage = ~pages, .size = 32, .alignment = 8192, .deallocator = page_deallocator).allocation
    if page_allocation.data.address % 8192 != 0 { status_code = 2 }
    deinit(.self = $&page_allocation)
}
