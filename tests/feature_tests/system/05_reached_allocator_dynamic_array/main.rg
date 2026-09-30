CountingAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    raw_addr :: UIntNative = UIntNative(.value = storage)
    self& = (
        .ffi = self&.ffi,
        .alloc_count = self&.alloc_count + 1,
        .dealloc_count = self&.dealloc_count,
    )
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&CountingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    raw_addr :: UIntNative = data.address
    free(.address = raw_addr, .ffi = self&.ffi)
    self& = (
        .ffi = self&.ffi,
        .alloc_count = self&.alloc_count,
        .dealloc_count = self&.dealloc_count + 1,
    )
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

exercise(
    .allocator: $&Allocator = reach allocator,
) -> () := {
    assume allocator

    arr ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 1))
    push(.self = $&arr, .value = 10)
    push(.self = $&arr, .value = 20)
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage :: CountingAllocator = (
        .ffi = system.ffi,
        .alloc_count = 0,
        .dealloc_count = 0,
    )
    assume allocator ::= $&allocator_storage

    exercise()

    if allocator_storage.alloc_count != 2 or allocator_storage.dealloc_count != 2 {
        status_code = 99
        return
    }
    status_code = allocator_storage.alloc_count * 10 + allocator_storage.dealloc_count
}
