main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation ::= unwrap_or_abort(.value = allocate(.self = system.page_allocator, .size = 32, .alignment = 8))
    allocation.size = 1000
    slot ::= allocation_slot#(.t: UIntNative)(.allocation = &allocation, .index = 4).slot
    deinit(.self = $&allocation)
}
