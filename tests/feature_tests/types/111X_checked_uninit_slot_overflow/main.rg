main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation ::= unwrap_or_abort(.value = allocate(.self = system.page_allocator, .size = 32, .alignment = 8))
    zero :: UIntNative = 0
    index ::= zero - 1
    slot ::= allocation_slot#(.t: UIntNative)(.allocation = &allocation, .index = index).slot
    deinit(.self = $&allocation)
}
