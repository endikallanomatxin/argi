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

DummyInput : Type = ()

read_line(
    .self: $&DummyInput,
    .allocator: $&Allocator = #reach allocator, system.allocator,
) -> (.line: String) := {
    line = String(.length = 2)
    bytes_set(.string = $&line, .index = 0, .value = 79)
    bytes_set(.string = $&line, .index = 1, .value = 75)
}

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (
        .alloc_count = 0,
        .dealloc_count = 0,
    )
    stdin :: DummyInput = DummyInput()

    line ::= read_line(.self = $&stdin, .allocator = $&allocator)
    first ::= bytes_get(.string = &line, .index = 0).byte
    second ::= bytes_get(.string = &line, .index = 1).byte
    deinit(.self = $&line, .allocator = $&allocator)

    if first != 79 {
        status_code = 1
        return
    }

    if second != 75 {
        status_code = 2
        return
    }

    status_code = allocator.alloc_count * 10 + allocator.dealloc_count
}
