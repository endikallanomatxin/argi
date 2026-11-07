main := (.system: System) -> () {
    allocator ::= CAllocator(.ffi = system.ffi)
    deallocator ::= to_virtual#(Deallocator)($&allocator)
    bytes :: [3]UIntNative = (8, 8, 8)
    alias ::= trusted_mutable_reinterpret_reference#(.from: [3]UIntNative, .to: AcquiredStorage)(.base = $&bytes)
    forged ::= ~alias&
    allocation ::= establish_allocation(.storage = ~forged, .size = 8, .alignment = 8, .deallocator = deallocator)
}
