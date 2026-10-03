main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: CAllocator
    allocator = CAllocator(.ffi = system.ffi)
    zero :: UIntNative = 0
    too_large ::= zero - 1
    failed ::= acquire_heap_storage(.size = too_large, .alignment = 8, .ffi = system.ffi)
    match failed {
        ..error _ {}
        ..ok ~ storage {
            free(.address = acquired_storage_address(.storage = &storage).address, .ffi = system.ffi)
            status_code = 1
        }
    }
    page_failed ::= acquire_page_storage(.memory = system.memory, .size = too_large, .alignment = 8)
    match page_failed {
        ..error _ {}
        ..ok ~ storage { status_code = 2 }
    }
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = system.memory)
    empty ::= unwrap_or_abort(.value = acquire_page_storage(.memory = system.memory, .size = 0, .alignment = 8))
    if acquired_storage_size(.storage = &empty).size != 0 { status_code = 3 }
    allocation ::= establish_allocation(.storage = ~empty, .size = 0, .alignment = 8, .deallocator = deallocator).allocation
    deinit(.self = $&allocation)
    marker :: UInt8 = 0
    inherited ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    raw ::= establish_inherited_storage(.storage = ~inherited, .root = erase_reference#(.t: UInt8)(.base = &marker).reference).raw
    free(.address = raw.address, .ffi = system.ffi)
}
