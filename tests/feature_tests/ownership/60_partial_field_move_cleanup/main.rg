CountingAllocator : Type = (
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.allocation: Allocation) := {
    storage ::= malloc(.size = size)
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = storage)
    self& = (
        .alloc_count = self&.alloc_count + 1,
        .dealloc_count = self&.dealloc_count,
    )
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation = establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
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
CountingAllocator implements Deallocator

Pair : Type = (
    .a: Allocation
    .b: Allocation
)

Outer : Type = (
    .pair: Pair
)

run_branch(.allocator: $&CountingAllocator, .condition: Bool) -> () := {
    pair ::= Pair(
        .a = allocate(.self = allocator, .size = 1),
        .b = allocate(.self = allocator, .size = 1),
    )
    if condition {
        taken ::= ~pair.a
    }
}

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = CountingAllocator()

    if 1 == 1 {
        pair ::= Pair(
            .a = allocate(.self = $&allocator, .size = 1),
            .b = allocate(.self = $&allocator, .size = 1),
        )
        taken ::= ~pair.a
    }

    if 1 == 1 {
        pair ::= Pair(
            .a = allocate(.self = $&allocator, .size = 1),
            .b = allocate(.self = $&allocator, .size = 1),
        )
        deinit(.self = $&pair.a)
    }

    run_branch(.allocator = $&allocator, .condition = true)
    run_branch(.allocator = $&allocator, .condition = false)

    if 1 == 1 {
        outer ::= Outer(.pair = Pair(
            .a = allocate(.self = $&allocator, .size = 1),
            .b = allocate(.self = $&allocator, .size = 1),
        ))
        taken ::= ~outer.pair.a
    }

    if 1 == 1 {
        pair ::= Pair(
            .a = allocate(.self = $&allocator, .size = 1),
            .b = allocate(.self = $&allocator, .size = 1),
        )
        taken ::= ~pair.a
        pair.a = allocate(.self = $&allocator, .size = 1)
    }

    if allocator.alloc_count != 13 {
        status_code = 1
        return
    }
    if allocator.dealloc_count != 13 {
        status_code = 2
        return
    }
    status_code = 0
}
