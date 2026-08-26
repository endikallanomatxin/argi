..out_of_memory

Allocator : Abstract = (
    allocate(.self: $&Self, .size: UIntNative) -> (.allocation: Allocation)
)

Deallocator : Abstract = (
    deallocate(.self: $&Self, .data: $&UInt8, .size: UIntNative) -> ()
)

allocate_fallible(
    .self: $&Allocator,
    .size: UIntNative,
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    allocation ::= allocate(.self = self, .size = size)
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = allocation.data)
    if raw_addr == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    result = ..ok ~allocation
}

CAllocator : Type = ()

init(.p: $&CAllocator) -> () := {
}

allocate(.self: $&CAllocator, .size: UIntNative) -> (.allocation: Allocation) := {
    storage ::= malloc(.size = size)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation = establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
}

deallocate(.self: $&CAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.pointer = cast#(.to: &Any)(.value = raw_addr))
}

CAllocator implements Allocator
CAllocator implements Deallocator
Allocator defaultsto CAllocator

Allocation : Type = (
    --
    -- Low-level owning heap allocation.
    --
    -- This is the common base intended for heap-owning standard-library types
    -- such as dynamic lists, strings, maps, and other contiguous containers.
    --
    -- `Allocation` owns raw bytes. It does not by itself imply any element
    -- type, shape, or view semantics.
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
    .storage: $&Any,
    .size: UIntNative,
    .deallocator: Virtual#(.abstract: Deallocator),
) -> (.allocation: Allocation) := {
    data ::= cast#(.to: $&UInt8)(.value = cast#(.to: UIntNative)(.value = storage))
    allocation = (
        .data = data,
        .size = size,
        .deallocator = deallocator,
    )
}

allocate_owned(
    .self: $&Allocator,
    .size: UIntNative,
) -> (.allocation: Allocation) := {
    allocation = allocate(.self = self, .size = size)
}

deinit(
    .self: $&Allocation,
) -> () := {
    if self&.size > 0 {
        deallocate(.self = $&self&.deallocator, .data = self&.data, .size = self&.size)
    }
}
