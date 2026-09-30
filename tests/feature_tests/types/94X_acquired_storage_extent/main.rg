main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: CAllocator
    init(.p = $&allocator, .ffi = system.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&allocator)
    storage ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    allocation ::= establish_allocation(.storage = ~storage, .size = 16, .alignment = 8, .deallocator = deallocator).allocation
    deinit(.self = $&allocation)
}
