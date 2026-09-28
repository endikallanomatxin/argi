main(.system: System) -> (.status_code: Int32) := {
    c_allocator ::= CAllocator(.ffi = system.ffi)
    storage ::= malloc(.size = 1, .ffi = system.ffi)
    moved ::= ~storage
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = $&c_allocator)
    allocation ::= establish_allocation(.storage = moved, .size = 1, .alignment = 1, .deallocator = deallocator)
    deinit(.self = $&allocation)
    status_code = 0
}
