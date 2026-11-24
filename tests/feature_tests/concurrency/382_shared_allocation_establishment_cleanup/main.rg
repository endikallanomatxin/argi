main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    {
        deallocator ::= Virtual#(Deallocator)(shared)
        storage ::= unwrap_or_abort(acquire_heap_storage(.size = 64, .alignment = 16, .ffi = system.ffi))
        allocation ::= establish_allocation(.storage = ~storage, .size = 64, .alignment = 16, .deallocator = deallocator)
        if allocation.size != 64 { abort }
    }
    recover_ordinary(.owner = $&allocator)
}
