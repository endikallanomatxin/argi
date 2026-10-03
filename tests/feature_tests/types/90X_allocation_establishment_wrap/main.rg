main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&allocator)
    zero :: UIntNative = 0
    address ::= zero - 8
    allocation ::= trusted_establish_allocation(.storage = address, .size = 16, .alignment = 8, .deallocator = deallocator).allocation
    deinit(.self = $&allocation)
}
