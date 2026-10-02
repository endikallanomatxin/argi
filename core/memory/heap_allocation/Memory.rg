-- Page mappings retain the foreign-call authorization used to acquire them.
Memory : Type = (
    ._ffi: $&ForeignFunctionInterface
    ._page_size: UIntNative
)

-- Trimming an aligned page mapping keeps the same acquisition authorization.
-- The platform boundary proves this address is a subrange of base's mapping.
_trusted_acquisition_subaddress(.base: UIntNative, .address: UIntNative) -> (.result: UIntNative) := {
    result = address
}

once init(.p: $&Memory, .ffi: $&ForeignFunctionInterface = reach ffi) -> () := {
    p&._ffi = ffi
    p&._page_size = _memory_getpagesize().size
    if p&._page_size == 0 { p&._page_size = 4096 }
}

_memory_map_aligned(
    .size: UIntNative,
    .alignment: UIntNative,
    .page_size: UIntNative,
) -> (.result: Errable#(.t: AcquiredStorage, .reasons: (..out_of_memory))) := {
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
    extra :: UIntNative = 0
    if alignment > page_size { extra = alignment - page_size }
    request_size ::= mapped_size + extra
    if request_size < mapped_size {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    mapped_address ::= _memory_map_anonymous(.length = request_size).address
    if mapped_address + 1 == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    if mapped_address + request_size < mapped_address { abort }
    address :: UIntNative = mapped_address
    if alignment > page_size {
        remainder ::= mapped_address % alignment
        if remainder != 0 {
            padding ::= alignment - remainder
            address = mapped_address + padding
            if address < mapped_address { abort }
            if _memory_munmap(.address = mapped_address, .length = padding).status != 0 { abort }
        }
        mapped_end ::= mapped_address + request_size
        used_end ::= address + mapped_size
        if used_end < mapped_end {
            if _memory_munmap(.address = used_end, .length = mapped_end - used_end).status != 0 { abort }
        }
    }
    certified ::= _trusted_acquisition_subaddress(.base = mapped_address, .address = address).result
    result = ..ok (._address = certified, ._size = mapped_size, ._alignment = alignment)
}

map_pages(.self: $&Memory, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    assume ffi := self&._ffi
    physical_size ::= page_allocator_round_up(.size = size, .alignment = self&._page_size).rounded
    mapped ::= _memory_map_aligned(.size = size, .alignment = alignment, .page_size = self&._page_size)
    match mapped {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ storage {
            deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
            allocation ::= establish_allocation(.storage = ~storage, .size = physical_size, .alignment = alignment, .deallocator = deallocator)
            result = ..ok ~allocation
        }
    }
}

deallocate(.self: $&Memory, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    assume ffi := self&._ffi
    physical_size ::= page_allocator_round_up(.size = size, .alignment = self&._page_size).rounded
    if _memory_munmap(.address = data.address, .length = physical_size).status != 0 { abort }
}
Memory implements Deallocator
