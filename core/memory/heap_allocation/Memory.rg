-- Page mappings retain the foreign-call authorization used to acquire them.
Memory: Type = (
    ._ffi       : $&ForeignFunctionInterface
    ._page_size : UIntNative
)

-- Trimming an aligned page mapping keeps the same acquisition authorization.
-- The platform boundary proves this address is a subrange of base's mapping.
_trusted_acquisition_subaddress(.base: UIntNative, .address: UIntNative) -> (.result: UIntNative) := {
    result = address
}

once Memory init(.ffi: $&ForeignFunctionInterface = reach ffi) -> (.result: Memory) := {
    result._ffi = ffi
    result._page_size = _memory_getpagesize().size

    if result._page_size == 0 { result._page_size = 4096 }
}

_memory_map_aligned(
        .size      : UIntNative,
        .alignment : UIntNative,
        .page_size : UIntNative,
    ) -> (
        .result : Errable#(AcquiredStorage, (..out_of_memory))
    ) := {
    _require_allocation_alignment(.alignment = alignment)

    if page_size == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    mapped_size ::= page_allocator_round_up(.size = size, .alignment = page_size).rounded

    if mapped_size < size or mapped_size == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    address ::= _memory_acquire_aligned(.length = mapped_size, .alignment = alignment).address

    if address + 1 == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    result = ..ok(._address = address, ._size = mapped_size, ._alignment = alignment)
}

map_pages(
        .self      : $&Memory,
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) := {
    assume ffi := self&._ffi
    physical_size ::= page_allocator_round_up(.size = size, .alignment = self&._page_size).rounded
    mapped ::= _memory_map_aligned(
        .size      = size
        .alignment = alignment
        .page_size = self&._page_size
    )

    match mapped {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~storage {
            deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(
                .value = self
            )
            allocation ::= establish_allocation(
                .storage     = ~storage
                .size        = physical_size
                .alignment   = alignment
                .deallocator = deallocator
            )
            result = ..ok ~allocation
        }
    }
}

deallocate(
        .self      : $&Memory,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () := {
    assume ffi := self&._ffi
    physical_size ::= page_allocator_round_up(.size = size, .alignment = self&._page_size).rounded

    if _memory_release_aligned(.address = data.address, .length = physical_size).status != 0 {
        abort
    }
}

Memory implements Deallocator
