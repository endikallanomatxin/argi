main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    storage ::= malloc(.size = 1, .ffi = system.ffi)
    alias ::= storage
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = $&allocator_storage)
    first ::= trusted_establish_allocation(.storage = storage, .size = 1, .alignment = 1, .deallocator = deallocator)
    second ::= trusted_establish_allocation(.storage = alias, .size = 1, .alignment = 1, .deallocator = deallocator)
    deinit(.self = $&first)
    deinit(.self = $&second)
    status_code = 0
}
