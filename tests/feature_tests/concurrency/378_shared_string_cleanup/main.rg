main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    {
        local: String = unwrap_or_abort(string_with_length(.allocator = Virtual#(Allocator)($&allocator), .length = 3))
        if unwrap_or_abort(bytes_get(.view = &local, .index = 2)) != 0 { abort }
    }
    shared ::= $$&allocator
    {
        text: String = unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 3))
    }
    recover_ordinary(.owner = $&allocator)
}
