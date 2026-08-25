..out_of_memory

Allocator : Abstract = (
    allocate(.self: $&Self, .size: UIntNative) -> (.data: $&UInt8)
    deallocate(.self: $&Self, .data: $&UInt8, .size: UIntNative) -> ()
)

allocate_fallible(
    .self: $&Allocator,
    .size: UIntNative,
) -> (.result: Errable#(.t: UIntNative, .reasons: (..out_of_memory))) := {
    data ::= allocate(.self = self, .size = size)
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = data)
    if raw_addr == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    result = ..ok raw_addr
}

CAllocator : Type = ()

init(.p: $&CAllocator) -> () := {
}

allocate(.self: $&CAllocator, .size: UIntNative) -> (.data: $&UInt8) := {
    allocation ::= malloc(.size = size)
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = allocation)
    data = cast#(.to: $&UInt8)(.value = raw_addr)
}

deallocate(.self: $&CAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.pointer = cast#(.to: &Any)(.value = raw_addr))
}

CAllocator implements Allocator
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
)

-- Compiler-owned temporal boundary used after a physical allocator has
-- returned backing storage. The Allocation value owns the new root; its data
-- field only depends on it.
establish_allocation(
    .data: $&UInt8,
    .size: UIntNative,
) -> (.allocation: Allocation) := {
    allocation = (
        .data = data,
        .size = size,
    )
}

deinit(
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&Allocation,
) -> () := {
    if self&.size > 0 {
        deallocate(.self = allocator, .data = self&.data, .size = self&.size)
    }
}
