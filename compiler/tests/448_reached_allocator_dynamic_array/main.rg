CountingAllocator : Type = (
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.data: $&UInt8) := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = size))
    self& = (
        .alloc_count = self&.alloc_count + 1,
        .dealloc_count = self&.dealloc_count,
    )
    data = cast#(.to: $&UInt8)(.value = raw_addr)
}

deallocate(.self: $&CountingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.pointer = cast#(.to: &Any)(.value = raw_addr))
    self& = (
        .alloc_count = self&.alloc_count,
        .dealloc_count = self&.dealloc_count + 1,
    )
}

CountingAllocator implements Allocator

exercise(
    .allocator: $&Allocator = #reach allocator,
) -> () := {
    arr ::= DynamicArray#(.t: Int32)(.capacity = 1)
    push(.self = $&arr, .value = 10)
    push(.self = $&arr, .value = 20)
}

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (
        .alloc_count = 0,
        .dealloc_count = 0,
    )

    exercise()

    status_code = allocator.alloc_count * 10 + allocator.dealloc_count
}
