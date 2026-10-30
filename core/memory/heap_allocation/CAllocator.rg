CAllocator := (
    .ffi : $&ForeignFunctionInterface
)

CAllocatorInitArgs: Type = (.ffi: $&ForeignFunctionInterface)

implement Init#(CAllocator, CAllocatorInitArgs) (
    .Result : Type = CAllocator

    .init = CAllocatorInitArgs -> (.result: Result) {
        _init_ffi ::= ffi
        result.ffi = _init_ffi
    }
)

implement Allocator#(CAllocator) (
    .allocate = (.self: $&CAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) {

        acquired ::= acquire_heap_storage(
            .size = size, .alignment = alignment, .ffi = self&.ffi
        )

        match acquired {
            ..error _ { result = ..error(.reason = ..out_of_memory) }
            ..ok ~storage {
                deallocator :: Virtual#(Deallocator) = to_virtual#(.contract: Deallocator)(
                    .value = self
                )
                allocation ::= establish_allocation(
                    .storage     = ~storage
                    .size        = size
                    .alignment   = alignment
                    .deallocator = deallocator
                )
                result = ..ok ~allocation
            }
        }
    }
)

implement Deallocator#(CAllocator) (
    .deallocate = (
        .self      : $&CAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        aligned_free(.address = data.address, .ffi = self&.ffi)
    }
)
