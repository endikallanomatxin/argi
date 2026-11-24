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

        deallocator ::= Virtual#(Deallocator)(self)
        result = _allocate_c_storage(.ffi = self&.ffi, .deallocator = deallocator, .size = size, .alignment = alignment)
    }
)

implement Deallocator#($&CAllocator) (
    ._deallocate = (
        .self      : $&CAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        _release_c_storage(.address = data.address, .ffi = self&.ffi)
    }
)

-- The C heap synchronizes its own metadata. The FFI capability stays live
-- through each allocation's retained deallocator.
implement ConcurrentAlias#(CAllocator) ()

implement Deallocator#($$&CAllocator) (
    ._deallocate = (
        .self: $$&CAllocator, .data: RawPointer#(UInt8), .size: UIntNative, .alignment: UIntNative
    ) -> () {
        view ::= trusted_concurrent_view(.shared = self)
        _release_c_storage(.address = data.address, .ffi = view&.ffi)
    }
)

-- The platform heap synchronizes its own metadata. This private import
-- releases the block supplied by the caller under its release custody.
_release_c_storage(.address: UIntNative) -> (): CFunction(.symbol = "_argi_c_aligned_release") where {
    no_access()
    isolated()
}

allocate_shared_c_storage := (
    .self: $$&CAllocator, .size: UIntNative, .alignment: UIntNative, .zeroed: Bool = false
) -> (.result: Errable#(Allocation, (..out_of_memory))) {
    view ::= trusted_concurrent_view(.shared = self)
    deallocator ::= Virtual#(Deallocator)(self)
    result = _allocate_c_storage(.ffi = view&.ffi, .deallocator = deallocator, .size = size, .alignment = alignment, .zeroed = zeroed)
}

_allocate_c_storage := (
    .ffi: $&ForeignFunctionInterface, .deallocator: Virtual#(Deallocator),
    .size: UIntNative, .alignment: UIntNative, .zeroed: Bool = false
) -> (.result: Errable#(Allocation, (..out_of_memory))) {
    acquired ::= acquire_heap_storage(.size = size, .alignment = alignment, .ffi = ffi, .zeroed = zeroed)
    match acquired {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~storage {
            allocation ::= establish_allocation(
                .storage = ~storage, .size = size, .alignment = alignment, .deallocator = deallocator
            )
            result = ..ok ~allocation
        }
    }
}
