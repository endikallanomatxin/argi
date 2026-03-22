Allocator : Abstract = (
    allocate(.self: $&Self, .size: UIntNative) -> (.data: $&UInt8)
    deallocate(.self: $&Self, .data: $&UInt8, .size: UIntNative) -> ()
)

DirectAllocator : Type = ()

init(.p: $&DirectAllocator) -> () := {
}

allocate(.self: $&DirectAllocator, .size: UIntNative) -> (.data: $&UInt8) := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = size))
    data = cast#(.to: $&UInt8)(.value = raw_addr)
}

deallocate(.self: $&DirectAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.pointer = cast#(.to: &Any)(.value = raw_addr))
}

DirectAllocator implements Allocator
Allocator defaultsto DirectAllocator

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
