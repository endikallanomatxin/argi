Forward#(.T: Type): Contract = (
    .forward: (.self: &T, .storage: AcquiredStorage) -> (.result: AcquiredStorage)
        where transfers(result, storage)
)
Provider := (.marker: UInt8)
implement Forward#(Provider) (
    .forward = (.self: &Provider, .storage: AcquiredStorage) -> (.result: AcquiredStorage) {
        result = ~storage
    }
)
establish_indirect := (.storage: $&AcquiredStorage, .deallocator: Virtual#(Deallocator)) -> (.result: Allocation) {
    acquired ::= ~storage&
    result = establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
}
main := (.system: System) -> () {
    provider ::= Provider(0)
    forwarder ::= to_virtual#(Forward)(&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= to_virtual#(Deallocator)($&allocator)
    acquired ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    forwarded ::= Forward#().forward(&forwarder, .storage = ~acquired)
    allocation ::= establish_indirect(.storage = $&forwarded, .deallocator = deallocator)
    slot ::= trusted_establish_allocation_slot#(.t: UInt64)(
        .allocation = &allocation,
        .slot = raw_pointer#(.t: UInt64)(.address = allocation.data.address),
        .anchor = allocation.anchor
    )
    slot& = 42
    if slot& != 42 { abort }
}
