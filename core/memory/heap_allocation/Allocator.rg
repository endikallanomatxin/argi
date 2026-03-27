Allocator : Abstract = (
    allocate(.self: $&Self, .size: UIntNative) -> (.data: $&UInt8)
    deallocate(.self: $&Self, .data: $&UInt8, .size: UIntNative) -> ()
)

CAllocator : Type = ()

init(.p: $&CAllocator) -> () := {
}

allocate(.self: $&CAllocator, .size: UIntNative) -> (.data: $&UInt8) := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = size))
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

deinit(
    .allocator: $&Allocator = #reach allocator, system.allocator,
    .self: $&Allocation,
) -> () := {
    if self&.size > 0 {
        deallocate(.self = allocator, .data = self&.data, .size = self&.size)
    }

    self& = (
        .data = self&.data,
        .size = 0,
    )
}
