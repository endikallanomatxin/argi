main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation ::= unwrap_or_abort(.value = allocate(.self = system.page_allocator, .size = 32, .alignment = 8))
    address ::= allocation.data.address + 32
    raw ::= raw_pointer#(.t: UIntNative)(.address = address).raw
    slot ::= establish_allocation_slot#(.t: UIntNative)(.allocation = &allocation, .slot = raw, .anchor = allocation.anchor).reference
    -- The guard must reject the slot without reading or writing through it.
    deinit(.self = $&allocation)
}
