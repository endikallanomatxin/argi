CountingAllocator : Type = (
    .last_alloc_size: UIntNative = 0
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.data: $&UInt8) := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = size))
    self& = (
        .last_alloc_size = size,
        .alloc_count = self&.alloc_count + 1,
        .dealloc_count = self&.dealloc_count,
    )
    data = cast#(.to: $&UInt8)(.value = raw_addr)
}

deallocate(.self: $&CountingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.pointer = cast#(.to: &Any)(.value = raw_addr))
    self& = (
        .last_alloc_size = self&.last_alloc_size,
        .alloc_count = self&.alloc_count,
        .dealloc_count = self&.dealloc_count + 1,
    )
}

CountingAllocator implements Allocator

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (
        .last_alloc_size = 0,
        .alloc_count = 0,
        .dealloc_count = 0,
    )

    text ::= String(.allocator = $&allocator, .length = 3)
    if allocator.last_alloc_size != 4 {
        status_code = 1
        return
    }

    deinit(.self = $&text, .allocator = $&allocator)
    if allocator.dealloc_count != 1 {
        status_code = 2
        return
    }

    status_code = 0
}
