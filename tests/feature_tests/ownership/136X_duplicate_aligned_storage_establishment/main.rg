main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    storage ::= aligned_alloc(.alignment = 8, .size = 8, .ffi = system.ffi)
    alias ::= storage
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = $&allocator_storage)
    first ::= establish_allocation(.storage = storage, .size = 8, .alignment = 8, .deallocator = deallocator)
    second ::= establish_allocation(.storage = alias, .size = 8, .alignment = 8, .deallocator = deallocator)
    deinit(.self = $&first)
    deinit(.self = $&second)
    status_code = 0
}
