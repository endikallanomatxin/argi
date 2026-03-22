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
    --
    -- Intended later:
    -- .allocator : &Allocator
    --
    -- The current compiler still does not support storing a pointer to an
    -- abstract type cleanly in a runtime field, so `Allocation` keeps only the
    -- raw memory handle and size for now.
)

allocation_init (.size: UIntNative) -> (.allocation: Allocation) := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = size))
    allocation = (
        .data = cast#(.to: $&UInt8)(.value = raw_addr),
        .size = size,
    )
}

allocation_deinit (.allocation: Allocation) -> () := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = allocation.data)
    free(.pointer = cast#(.to: &Any)(.value = raw_addr))
}
