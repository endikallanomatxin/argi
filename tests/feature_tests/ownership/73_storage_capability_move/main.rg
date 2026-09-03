main(.system: System) -> (.status_code: Int32) := {
    storage ::= malloc(.size = 1)
    moved ::= ~storage
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = system.allocator)
    allocation ::= establish_allocation(.storage = moved, .size = 1, .deallocator = deallocator)
    deinit(.self = $&allocation)
    status_code = 0
}
