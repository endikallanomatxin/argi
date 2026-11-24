EmptyStorage := (.marker: UInt8)
implement ConcurrentAlias#(EmptyStorage) ()

implement Deallocator#($&EmptyStorage) (
    ._deallocate = (.self: $&EmptyStorage, .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative) -> () {
        if size != 0 { abort }
    }
)

implement Deallocator#($$&EmptyStorage) (
    ._deallocate = (.self: $$&EmptyStorage, .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative) -> () {
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
    trusted_deallocate_raw(.ffi = system.ffi, .provider = local_release, .data = empty, .size = 0, .alignment = 1)
    trusted_deallocate_raw(.ffi = system.ffi, .provider = shared_release, .data = empty, .size = 0, .alignment = 1)
    recover_ordinary(.owner = $&shared)
}
