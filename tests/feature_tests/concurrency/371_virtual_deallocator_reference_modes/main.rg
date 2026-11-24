EmptyStorage := (.marker: UInt8)
implement ConcurrentAlias#(EmptyStorage) ()

implement Deallocator#($&EmptyStorage) (
    .deallocate = (.self: $&EmptyStorage, .request: Deallocation) -> () {
        layout ::= deallocation_layout(&request)
        size ::= layout.size
        if size != 0 { abort }
    }
)

implement Deallocator#($$&EmptyStorage) (
    .deallocate = (.self: $$&EmptyStorage, .request: Deallocation) -> () {
        layout ::= deallocation_layout(&request)
        size ::= layout.size
        if size != 0 { abort }
    }
)

forward_deallocator := (.release: Virtual#(Deallocator)) -> (.result: Virtual#(Deallocator)) {
    result = release
}

main := (.system: System) -> () {
    local ::= EmptyStorage(0)
    shared ::= EmptyStorage(0)
    local_release ::= Virtual#(Deallocator)($&local)
    shared_release ::= forward_deallocator(Virtual#(Deallocator)($$&shared)).result
    empty ::= raw_pointer#(UInt8)(.address = 0).raw
    local_request ::= trusted_deallocation_request(.data = empty, .size = 0, .alignment = 1, .ffi = system.ffi)
    local_release.deallocate(.request = ~local_request)
    shared_request ::= trusted_deallocation_request(.data = empty, .size = 0, .alignment = 1, .ffi = system.ffi)
    shared_release.deallocate(.request = ~shared_request)
    recover_ordinary(.owner = $&shared)
}
