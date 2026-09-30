main(.system: System) -> (.status_code: Int32 = 0) := {
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = system.memory)
    storage ::= unwrap_or_abort(.value = acquire_page_storage(.memory = system.memory, .size = 8, .alignment = 8))
    allocation ::= establish_allocation(.storage = storage, .size = 16, .alignment = 8, .deallocator = deallocator).allocation
    deinit(.self = $&allocation)
}
