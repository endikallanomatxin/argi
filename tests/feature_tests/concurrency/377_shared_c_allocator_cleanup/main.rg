main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    {
        allocation ::= unwrap_or_abort(allocate_shared_c_storage(.self = shared, .size = 64, .alignment = 16))
        if allocation.size != 64 { abort }
    }
    recover_ordinary(.owner = $&allocator)
}
