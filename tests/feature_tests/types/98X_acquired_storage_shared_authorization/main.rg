main(.system: System) -> (.status_code: Int32 = 0) := {
    assume ffi := system.ffi
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&allocator)
    storage ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    allocation ::= establish_allocation(.storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator).allocation
    marker :: UInt8 = 0
    raw ::= establish_inherited_storage(.storage = ~storage, .root = erase_reference#(.t: UInt8)(.base = &marker).reference).raw
    deinit(.self = $&allocation)
}
