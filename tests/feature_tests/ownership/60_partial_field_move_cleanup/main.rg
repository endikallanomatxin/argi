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

Pair : Type = (
    .a: Allocation
    .b: Allocation
)

Outer : Type = (
    .pair: Pair
)

make_pair(.allocator: $&CountingAllocator) -> (.result: Errable#(.t: Pair, .reasons: (..out_of_memory))) := {
    assume allocator

    first_result ::= allocate(.self = allocator, .size = 1)
    match first_result {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ first_payload {
            first ::= ~first_payload
            second_result ::= allocate(.self = allocator, .size = 1)
            match second_result {
                ..error _ {
                    deinit(.self = $&first)
                    result = ..error(.reason = ..out_of_memory)
                }
                ..ok ~ second_payload {
                    result = ..ok Pair(.a = ~first, .b = ~second_payload)
                }
            }
        }
    }
}

run_branch(.allocator: $&CountingAllocator, .condition: Bool) -> (.result: Errable#(.t: Void, .reasons: (..out_of_memory))) := {
    assume allocator

    first_result ::= allocate(.self = allocator, .size = 1)
    match first_result {
    ..error _ { result = ..error(.reason = ..out_of_memory) }
    ..ok ~ first_payload {
    second_result ::= allocate(.self = allocator, .size = 1)
    match second_result {
    ..error _ {
        result = ..error(.reason = ..out_of_memory)
    }
    ..ok ~ second_payload {
        pair ::= Pair(.a = ~first_payload, .b = ~second_payload)
        if condition {
            taken ::= ~pair.a
        }
        result = ..ok Void()
    }
    }
    }
    }
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage :: CountingAllocator = CountingAllocator(.ffi = system.ffi)
    assume allocator ::= $&allocator_storage

    if 1 == 1 {
        pair_result ::= make_pair(.allocator = $&allocator_storage)
        if is(.value = pair_result, .variant = ..error) { status_code = 3 return }
        pair ::= ~pair_result..ok
        taken ::= ~pair.a
    }

    if 1 == 1 {
        pair_result ::= make_pair(.allocator = $&allocator_storage)
        if is(.value = pair_result, .variant = ..error) { status_code = 4 return }
        pair ::= ~pair_result..ok
        deinit(.self = $&pair.a)
    }

    first_branch ::= run_branch(.allocator = $&allocator_storage, .condition = true)
    second_branch ::= run_branch(.allocator = $&allocator_storage, .condition = false)
    if is(.value = first_branch, .variant = ..error) or is(.value = second_branch, .variant = ..error) { status_code = 5 return }

    if 1 == 1 {
        pair_result ::= make_pair(.allocator = $&allocator_storage)
        if is(.value = pair_result, .variant = ..error) { status_code = 6 return }
        outer ::= Outer(.pair = ~pair_result..ok)
        taken ::= ~outer.pair.a
    }

    if 1 == 1 {
        pair_result ::= make_pair(.allocator = $&allocator_storage)
        if is(.value = pair_result, .variant = ..error) { status_code = 7 return }
        pair ::= ~pair_result..ok
        taken ::= ~pair.a
        replacement ::= allocate(.self = $&allocator_storage, .size = 1)
        if is(.value = replacement, .variant = ..error) { status_code = 8 return }
        pair.a = ~replacement..ok
    }

    if allocator_storage.alloc_count != 13 {
        status_code = 1
        return
    }
    if allocator_storage.dealloc_count != 13 {
        status_code = 2
        return
    }
    status_code = 0
}
