Provider := (.ffi: $&ForeignFunctionInterface, .releases: $$&AtomicUInt32)

implement ConcurrentAlias#(Provider) ()

-- The platform heap release uses the same ABI as heap acquisition.
release(.address: UIntNative) -> (): CFunction(.symbol = "_argi_c_aligned_release") where {
    no_access()
}

implement Deallocator#($$&Provider) (
    ._deallocate = (
        .self: $$&Provider, .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative
    ) -> () {
        capability ::= trusted_concurrent_view(.shared = self)
        release(.address = data.address, .ffi = capability&.ffi)
        _ = shared_fetch_add(.self = capability&.releases, .value = 1)
    }
)

allocate := (.provider: $$&Provider, .ffi: $&ForeignFunctionInterface) -> (
    .result: Errable#(Allocation, (..out_of_memory))
) {
    receipt ::= acquire_heap_storage(.size = 1, .alignment = 1, .ffi = ffi, .zeroed = true)!
    deallocator ::= Virtual#(Deallocator)(provider)
    allocation ::= establish_allocation(.storage = ~receipt, .size = 1, .alignment = 1, .deallocator = deallocator)
    result = ..ok ~allocation
}
