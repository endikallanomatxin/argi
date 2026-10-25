CountingAllocator: Type = (
    .ffi : $&ForeignFunctionInterface
    .alloc_count   : Int32 = 0
    .dealloc_count : Int32 = 0
)

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage :: CountingAllocator = (
        .ffi = system.ffi
        .alloc_count   = 0
        .dealloc_count = 0
    )
    assume allocator ::= $&allocator_storage

    {
        value :: (.text: String, .missing: Bool)
        if 1 == 1 {
            value.text = unwrap_or_abort(
                .value = String(.allocator = $&allocator_storage, .length = 3)
            )
        }
    }

    if allocator_storage.alloc_count != 1 or allocator_storage.dealloc_count != 1 { abort }
    status_code = 42
}

implement Allocator#(CountingAllocator) (
    .allocate = (.self: $&CountingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) {
        storage ::= malloc(.size = size, .ffi = self&.ffi)
        raw_addr :: UIntNative = storage | convert#(.to: UIntNative)(_)
        self&.alloc_count = self&.alloc_count + 1
        deallocator :: Virtual#(.contract: Deallocator) = to_virtual#(.contract: Deallocator)(
            .value = self
        )
        allocation ::= trusted_establish_allocation(
            .storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator
        )
        result = ..ok ~allocation
    }
)

implement Deallocator#(CountingAllocator) (
    .deallocate = (
        .self      : $&CountingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        raw_addr :: UIntNative = data.address
        free(.address = raw_addr, .ffi = self&.ffi)
        self&.dealloc_count = self&.dealloc_count + 1
    }
)
