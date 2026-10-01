main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation ::= unwrap_or_abort(.value = allocate(.self = system.page_allocator, .size = 3))
    pointer ::= trusted_establish_allocation_slot#(.t: UInt8)(.allocation = &allocation, .slot = allocation.data, .anchor = allocation.anchor).reference
    pointer& = 97
    deinit(.self = $&allocation)
    observed ::= pointer&
}
