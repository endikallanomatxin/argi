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

Pair : Type = (
    .a: Allocation
    .b: Allocation
)

Outer : Type = (
    .pair: Pair
)

run_branch(.allocator: $&CountingAllocator, .condition: Bool) -> () := {
    pair ::= Pair(
        .a = allocate_owned(.self = allocator, .size = 1),
        .b = allocate_owned(.self = allocator, .size = 1),
    )
    if condition {
        taken ::= ~pair.a
    }
}

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = CountingAllocator()

    if 1 == 1 {
        pair ::= Pair(
            .a = allocate_owned(.self = $&allocator, .size = 1),
            .b = allocate_owned(.self = $&allocator, .size = 1),
        )
        taken ::= ~pair.a
    }

    if 1 == 1 {
        pair ::= Pair(
            .a = allocate_owned(.self = $&allocator, .size = 1),
            .b = allocate_owned(.self = $&allocator, .size = 1),
        )
        deinit(.self = $&pair.a, .allocator = $&allocator)
    }

    run_branch(.allocator = $&allocator, .condition = true)
    run_branch(.allocator = $&allocator, .condition = false)

    if 1 == 1 {
        outer ::= Outer(.pair = Pair(
            .a = allocate_owned(.self = $&allocator, .size = 1),
            .b = allocate_owned(.self = $&allocator, .size = 1),
        ))
        taken ::= ~outer.pair.a
    }

    if 1 == 1 {
        pair ::= Pair(
            .a = allocate_owned(.self = $&allocator, .size = 1),
            .b = allocate_owned(.self = $&allocator, .size = 1),
        )
        taken ::= ~pair.a
        pair.a = allocate_owned(.self = $&allocator, .size = 1)
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
