CountingAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = storage)
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

Wrapper : Type = (
    .text: String
)

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage :: CountingAllocator = (
        .ffi = system.ffi,
        .alloc_count = 0,
        .dealloc_count = 0,
    )
    assume allocator ::= $&allocator_storage

    if 1 == 1 {
        value : Wrapper = (
            .text = String(.allocator = $&allocator_storage, .length = 3),
        )
        if value.text.length != 3 {
            status_code = 1
            return
        }
    }

    status_code = allocator_storage.alloc_count * 10 + allocator_storage.dealloc_count
}
