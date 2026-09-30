main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: CAllocator
    init(.p = $&allocator, .ffi = system.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&allocator)
    allocation :: Allocation = (
        .data = raw_pointer#(.t: UInt8)(.address = 1).raw,
        .size = 8,
        .alignment = 1,
        .anchor = erase_reference#(.t: UInt8)(.base = &allocation_static_anchor).reference,
        .deallocator = deallocator,
        ._storage_address = 1,
        ._storage_size = 8,
        ._storage_alignment = 1,
    )
    deinit(.self = $&allocation)
}
