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

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (
        .alloc_count = 0,
        .dealloc_count = 0,
    )

    i :: Int32 = 0
    while i < 2 {
        text ::= String(.allocator = $&allocator, .length = 3)
        if text.length != 3 {
            status_code = 1
            return
        }
        i = i + 1
    }

    if allocator.alloc_count != 2 {
        status_code = 2
        return
    }

    if allocator.dealloc_count != 2 {
        status_code = 3
        return
    }

    status_code = 0
}
