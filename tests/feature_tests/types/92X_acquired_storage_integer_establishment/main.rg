main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&allocator)
    allocation ::= establish_allocation(.storage = ~123, .size = 8, .alignment = 8, .deallocator = deallocator).allocation
    deinit(.self = $&allocation)
}
