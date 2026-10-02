CountingAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .last_alloc_size: UIntNative = 0
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    raw_addr :: UIntNative = UIntNative(.value = storage)
    self& = (
        .ffi = self&.ffi,
        .last_alloc_size = size,
        .alloc_count = self&.alloc_count + 1,
        .dealloc_count = self&.dealloc_count,
    )
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= trusted_establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&CountingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    raw_addr :: UIntNative = data.address
    free(.address = raw_addr, .ffi = self&.ffi)
    self& = (
        .ffi = self&.ffi,
        .last_alloc_size = self&.last_alloc_size,
        .alloc_count = self&.alloc_count,
        .dealloc_count = self&.dealloc_count + 1,
    )
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage :: CountingAllocator = (
        .ffi = system.ffi,
        .last_alloc_size = 0,
        .alloc_count = 0,
        .dealloc_count = 0,
    )
    assume allocator ::= $&allocator_storage

    text ::= unwrap_or_abort(.value = String(.allocator = $&allocator_storage, .length = 3))
    if allocator_storage.last_alloc_size != 4 {
        status_code = 1
        return
    }

    deinit(.self = $&text, .allocator = $&allocator_storage)
    if allocator_storage.dealloc_count != 1 {
        status_code = 2
        return
    }

    status_code = 0
}
