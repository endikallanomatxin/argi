Acquire#(.T: Type): Contract = (
    .acquire: (.self: &T) -> (.result: AcquiredStorage) where owns(result)
)
Provider := (.ffi: $&ForeignFunctionInterface)
implement Acquire#(Provider) (
    .acquire = (.self: &Provider) -> (.result: AcquiredStorage) {
        result = unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = self&.ffi))
    }
)
main := (.system: System) -> () {
    provider ::= Provider(system.ffi)
    factory ::= to_virtual#(Acquire)(&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= to_virtual#(Deallocator)($&allocator)
    acquired ::= Acquire#().acquire(&factory)
    allocation ::= establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
}
