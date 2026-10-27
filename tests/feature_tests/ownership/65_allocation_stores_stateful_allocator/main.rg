unsafe_allocation := import ("../../_support/unsafe_allocation")

CountingAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .deallocations : Int32
)

main := (.system: System) -> (.status_code: Int32) {
    allocator_storage :: CountingAllocator = (.ffi = system.ffi, .deallocations = 0)
    assume allocator ::= $&allocator_storage
    result ::= allocate_bytes(.self = $&allocator_storage, .size = 1)
    match result {
        ..ok ~payload {
            allocation ::= ~payload
            byte_pointer_27 ::= unsafe_allocation.trusted_allocation_byte_rw(
                .allocation = $&allocation, .offset = 0
            ).reference
            byte_pointer_27&= 7
            deinit(.self = $&allocation)
        }
        ..error _ {
            status_code = 2
            return
        }
    }

    if allocator_storage.deallocations == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
}

implement Allocator#(CountingAllocator) (
    .allocate = (.self: $&CountingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
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

implement Deallocator#(CountingAllocator) (
    .deallocate = (
        .self      : $&CountingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        self&.deallocations = self&.deallocations + 1
        address :: UIntNative = data.address
        free(.address = address, .ffi = self&.ffi)
    }
)
