-- A successful acquisition certifies bytes, not initialized values or a
-- temporal owner. Moving the receipt transfers its authorization; establishment
-- consumes it before references to the acquired bytes can escape.
AcquiredStorage: Type = (
    ._address   : UIntNative
    ._size      : UIntNative
    ._alignment : UIntNative
)

-- The receipt owns establishment authority, not physical cleanup. Dropping it
-- requires explicit move semantics and does not release the acquired bytes;
-- the low-level caller must establish an owner or arrange trusted cleanup.
AcquiredStorage deinit(.self: $&AcquiredStorage) -> () := {}

-- This attaches acquired bytes to an existing temporal domain. The caller
-- arranges physical cleanup with that domain; no initialized T is created.
establish_inherited_storage(
        .storage : AcquiredStorage,
        .root    : &Any
    ) -> (
        .raw : RawPointer#(.t: UInt8)
    ) := {
    raw = trusted_establish_inherited_storage(.address = storage._address, .root = root).raw
}

acquired_storage_address(.storage: &AcquiredStorage) -> (.address: UIntNative) := {
    address = storage&._address
}

acquired_storage_size(.storage: &AcquiredStorage) -> (.size: UIntNative) := {
    size = storage&._size
}

acquired_storage_alignment(.storage: &AcquiredStorage) -> (.alignment: UIntNative) := {
    alignment = storage&._alignment
}

acquire_heap_storage(
        .size      : UIntNative,
        .alignment : UIntNative,
        .ffi       : $&ForeignFunctionInterface,
    ) -> (
        .result : Errable#(.t: AcquiredStorage, .reasons: (..out_of_memory))
    ) := {
    _require_allocation_alignment(.alignment = alignment)
    physical_alignment ::= alignment
    pointer_alignment ::= alignment_of(.type = UIntNative)

    if physical_alignment < pointer_alignment { physical_alignment = pointer_alignment }
    physical_size ::= size

    if physical_size == 0 { physical_size = 1 }
    remainder ::= physical_size % physical_alignment

    if remainder != 0 {
        padding ::= physical_alignment - remainder
        physical_size = physical_size + padding
        if physical_size < size {
            result = ..error(.reason = ..out_of_memory)
            return
        }
    }

    address ::= aligned_alloc(.alignment = physical_alignment, .size = physical_size, .ffi = ffi).address

    if address == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    if address + physical_size < address { abort }

    result = ..ok(._address = address, ._size = size, ._alignment = alignment)
}

acquire_page_storage(
        .memory    : $&Memory,
        .size      : UIntNative,
        .alignment : UIntNative,
    ) -> (
        .result : Errable#(.t: AcquiredStorage, .reasons: (..out_of_memory))
    ) := {
    assume ffi := memory&._ffi
    acquired ::= _memory_map_aligned(
        .size      = size
        .alignment = alignment
        .page_size = memory&._page_size
    )

    match acquired {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~storage {
            -- The caller receives the requested range, excluding page padding.
            storage._size = size
            result = ..ok ~storage
        }
    }
}
