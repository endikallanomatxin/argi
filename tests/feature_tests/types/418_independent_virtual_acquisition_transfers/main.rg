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
    first ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    second ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    first_address ::= acquired_storage_address(.storage = &first)
    first_receipt ::= Forward#().forward(&forwarder, .storage = ~first)
    second_receipt ::= Forward#().forward(&forwarder, .storage = ~second)
    -- Consuming the first authorization must not affect the independent second.
    first_owner ::= trusted_establish_allocation(.storage = first_address, .size = 8, .alignment = 8, .deallocator = deallocator)
    second_owner ::= establish_allocation(.storage = ~second_receipt, .size = 8, .alignment = 8, .deallocator = deallocator)
}
