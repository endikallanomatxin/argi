EmptyStorage := (.marker: UInt8)
implement ConcurrentAlias#(EmptyStorage) ()

implement Deallocator#($&EmptyStorage) (
    .deallocate = (.self: $&EmptyStorage, .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative) -> () {
        if size != 0 { abort }
    }
)

implement Deallocator#($$&EmptyStorage) (
    .deallocate = (.self: $$&EmptyStorage, .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative) -> () {
        if size != 0 { abort }
    }
)

forward_deallocator := (.release: Virtual#(Deallocator)) -> (.result: Virtual#(Deallocator)) {
    result = release
}

main := () -> () {
    local ::= EmptyStorage(0)
    shared ::= EmptyStorage(0)
    local_release ::= Virtual#(Deallocator)($&local)
    shared_release ::= forward_deallocator(Virtual#(Deallocator)($$&shared)).result
    empty ::= raw_pointer#(UInt8)(.address = 0).raw
    local_release.deallocate(.data = empty, .size = 0, .alignment = 1)
    shared_release.deallocate(.data = empty, .size = 0, .alignment = 1)
    recover_ordinary(.owner = $&shared)
}
