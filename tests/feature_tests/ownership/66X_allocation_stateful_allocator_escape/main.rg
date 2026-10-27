LocalAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .deallocations : Int32
)

make := (.ffi: $&ForeignFunctionInterface) -> (
    .result: Errable#(.t: Allocation, .reasons: (..out_of_memory))
) {
    allocator_storage :: LocalAllocator = (.ffi = ffi, .deallocations = 0)
    assume allocator ::= $&allocator_storage
    result = allocate_bytes(.self = $&allocator_storage, .size = 1)
}

main := (.system: System) -> (.status_code: Int32) {
    escaped ::= make(.ffi = system.ffi)
    status_code = 0
}

implement Allocator#(LocalAllocator) (
    .allocate = (.self: $&LocalAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result: Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) {
        storage ::= malloc(.size = size, .ffi = self&.ffi)
        address :: UIntNative = storage | convert#(.to: UIntNative)(_)
        deallocator :: Virtual#(.contract: Deallocator) = to_virtual#(.contract: Deallocator)(
            .value = self
        )
        allocation ::= trusted_establish_allocation(
            .storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator
        )
        result = ..ok ~allocation
    }
)

implement Deallocator#(LocalAllocator) (
    .deallocate = (
        .self      : $&LocalAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        self&.deallocations = self&.deallocations + 1
        address :: UIntNative = data.address
        free(.address = address, .ffi = self&.ffi)
    }
)
