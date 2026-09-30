main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation ::= unwrap_or_abort(.value = allocate(.self = system.page_allocator, .size = 32, .alignment = 8))
    end ::= allocation.data.address + allocation.size
    allocation.data.address = end
    raw ::= raw_pointer#(.t: UIntNative)(.address = end).raw
    slot ::= establish_allocation_slot#(.t: UIntNative)(.allocation = &allocation, .slot = raw, .anchor = allocation.anchor).reference
    deinit(.self = $&allocation)
}
