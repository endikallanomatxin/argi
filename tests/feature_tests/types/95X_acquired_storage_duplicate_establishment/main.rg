establish(.storage: AcquiredStorage, .deallocator: Virtual#(.abstract: Deallocator)) -> (.result: Allocation) := {
    result = establish_allocation(.storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator).allocation
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: CAllocator
    init(.p = $&allocator, .ffi = system.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&allocator)
    storage ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    alias ::= ~storage
    first ::= establish(.storage = ~storage, .deallocator = deallocator).result
    second ::= establish(.storage = ~alias, .deallocator = deallocator).result
    deinit(.self = $&first)
    deinit(.self = $&second)
}
