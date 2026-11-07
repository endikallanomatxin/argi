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
main := (.system: System) -> () {
    provider ::= Provider(0)
    forwarder ::= to_virtual#(Forward)(&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= to_virtual#(Deallocator)($&allocator)
    acquired ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    address ::= acquired_storage_address(.storage = &acquired)
    forwarded ::= Forward#().forward(&forwarder, .storage = ~acquired)
    checked_owner ::= establish_allocation(.storage = ~forwarded, .size = 8, .alignment = 8, .deallocator = deallocator)
    raw_owner ::= trusted_establish_allocation(.storage = address, .size = 8, .alignment = 8, .deallocator = deallocator)
}
