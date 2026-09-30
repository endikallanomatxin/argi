forward#(.t: Type)(.slot: MaybeUninit#(.t: t)) -> (.result: MaybeUninit#(.t: t)) := { result = slot }
main(.system: System) -> (.status_code: Int32 = 0) := {
    allocation ::= unwrap_or_abort(.value = allocate(.self = system.page_allocator, .size = 32, .alignment = 8))
    slot ::= allocation_slot#(.t: UIntNative)(.allocation = &allocation, .index = 3).slot
    forwarded ::= forward#(.t: UIntNative)(.slot = slot).result
    address ::= uninit_slot_address#(.t: UIntNative)(.slot = forwarded).address
    if address != allocation.data.address + 24 { status_code = 1 }
    deinit(.self = $&allocation)
}
