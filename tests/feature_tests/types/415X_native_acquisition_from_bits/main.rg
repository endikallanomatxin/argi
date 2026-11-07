Numbers: CStruct = (.address: UIntNative, .size: UIntNative, .alignment: UIntNative)
NoFree: Type = ()
implement Deallocator#(NoFree) (
    .deallocate = (.self: $&NoFree, .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative) -> () {}
)
Boundary(.bytes: Numbers) -> (): CFunctionPointer
establish(.bytes: Numbers) -> (): CFunction := {
    local ::= bytes
    alias ::= trusted_mutable_reinterpret_reference#(.from: Numbers, .to: AcquiredStorage)(.base = $&local)
    acquired ::= ~alias&
    allocator ::= NoFree()
    deallocator ::= Virtual#(Deallocator)($&allocator)
    allocation ::= establish_allocation(.storage = ~acquired, .size = 8, .alignment = 8, .deallocator = deallocator)
    slot ::= trusted_establish_allocation_slot#(UInt64)(
        .allocation = &allocation,
        .slot = raw_pointer#(UInt64)(.address = allocation.data.address),
        .anchor = allocation.anchor
    )
    slot& = 42
}
main := () -> () {
    callback ::= Boundary(.function = establish)
}
