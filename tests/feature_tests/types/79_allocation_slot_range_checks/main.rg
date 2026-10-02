main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation ::= unwrap_or_abort(.value = allocate(.self = system.page_allocator, .size = 32, .alignment = 8))
    address ::= allocation.data.address + 24
    raw ::= raw_pointer#(.t: UIntNative)(.address = address).raw
    slot ::= trusted_establish_allocation_slot#(.t: UIntNative)(.allocation = &allocation, .slot = raw, .anchor = allocation.anchor).reference
    slot& = 123
    if slot& != 123 { status_code = 1 }
    deinit(.self = $&allocation)
}
