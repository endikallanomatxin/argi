main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation ::= unwrap_or_abort(.value = allocate(.self = system.page_allocator, .size = 32, .alignment = 8))
    slot ::= allocation_slot#(.t: UIntNative)(.allocation = &allocation, .index = 0).slot
    value ::= slot&
    deinit(.self = $&allocation)
}
