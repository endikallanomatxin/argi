main(.system: System) -> (.status_code: Int32) := {
    storage ::= malloc(.size = 1)
    alias ::= storage
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = system.allocator)
    first ::= establish_allocation(.storage = storage, .size = 1, .deallocator = deallocator)
    second ::= establish_allocation(.storage = alias, .size = 1, .deallocator = deallocator)
    deinit(.self = $&first)
    deinit(.self = $&second)
    status_code = 0
}
