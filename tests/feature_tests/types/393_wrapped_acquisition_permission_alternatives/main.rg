Acquire#(.T: Type): Contract = (
    .acquire: (.self: &T) -> (.result: AcquiredStorage) where owns(result)
)
Provider := (.ffi: $&ForeignFunctionInterface)
implement Acquire#(Provider) (
    .acquire = (.self: &Provider) -> (.result: AcquiredStorage) {
        result = unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = self&.ffi))
    }
)
Box := (.receipt: AcquiredStorage)
forward := #(.T: Type) (.value: T) -> (.result: T) { result = ~value }
choose := (.flag: Bool, .first: Box, .second: Box) -> (.result: AcquiredStorage) {
    if flag { result = ~first.receipt } else { result = ~second.receipt }
}
wrapped := (.flag: Bool, .first: Box, .second: Box) -> (.result: AcquiredStorage) {
    selected ::= choose(.flag = flag, .first = ~first, .second = ~second)
    result = forward#(AcquiredStorage)(.value = ~selected)
}
main := (.system: System) -> () {
    provider ::= Provider(system.ffi)
    factory ::= Virtual#(Acquire)(&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= Virtual#(Deallocator)($&allocator)
    first ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 8, .alignment = 8, .ffi = system.ffi))
    second ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 16, .alignment = 8, .ffi = system.ffi))
    -- AcquiredStorage carries establishment permission, not cleanup. The
    -- false branch selects second; release the unselected first acquisition.
    first_address ::= acquired_storage_address(.storage = &first)
    acquired ::= wrapped(.flag = false, .first = Box(.receipt = ~first), .second = Box(.receipt = ~second))
    allocation ::= establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
    aligned_free(.address = first_address, .ffi = system.ffi)
}
