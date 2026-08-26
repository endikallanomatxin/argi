..out_of_memory

Allocator : Abstract = (
    allocate(.self: $&Self, .size: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory)))
)

Deallocator : Abstract = (
    deallocate(.self: $&Self, .data: $&UInt8, .size: UIntNative) -> ()
)

CAllocator : Type = ()

init(.p: $&CAllocator) -> () := {
}

allocate(.self: $&CAllocator, .size: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    physical_size ::= size
    if physical_size == 0 {
        physical_size = 1
    }
    address ::= malloc(.size = physical_size).address
    if address == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = address, .size = size, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&CAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.address = raw_addr)
}

CAllocator implements Allocator
CAllocator implements Deallocator
Allocator defaultsto CAllocator

Allocation : Type = (
    --
    -- Contiguous allocated storage together with the capability required for
    -- its physical cleanup.
    --
    -- The concrete allocate operation determines its temporal facts. A heap
    -- allocation can own a fresh root, while region-backed storage can depend
    -- on a shared root without owning an individual one.
    --
    -- The nominal type does not imply ownership, element type, shape, or view
    -- semantics.
    --
    -- Copying an `Allocation` by value should not be allowed unless an
    -- explicit `copy()` is provided by a higher-level owning type.
    --
    .data      : $&UInt8
    .size      : UIntNative
    .deallocator : Virtual#(.abstract: Deallocator)
)

-- Compiler-owned temporal boundary used after a physical allocator has
-- returned backing storage. The Allocation value owns the new root; its data
-- field only depends on it.
establish_allocation(
    .storage: UIntNative,
    .size: UIntNative,
    .deallocator: Virtual#(.abstract: Deallocator),
) -> (.allocation: Allocation) := {
    data ::= cast#(.to: $&UInt8)(.value = storage)
    allocation = (
        .data = data,
        .size = size,
        .deallocator = deallocator,
    )
}

deinit(
    .self: $&Allocation,
) -> () := {
    deallocate(.self = $&self&.deallocator, .data = self&.data, .size = self&.size)
}
