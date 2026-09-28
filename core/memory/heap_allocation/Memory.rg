-- OS page capability. It exposes memory operations, not arbitrary FFI calls.
Memory : Type = (
    ._page_size: UIntNative
)

once init(.p: $&Memory) -> () := {
    p&._page_size = _memory_getpagesize().size
    if p&._page_size == 0 { p&._page_size = 4096 }
}

_memory_getpagesize() -> (.size: UIntNative) : ExternFunction
_memory_mmap(.hint: UIntNative, .length: UIntNative, .protection: Int32, .flags: Int32, .file_descriptor: Int32, .offset: UIntNative) -> (.address: UIntNative) : ExternFunction
_memory_munmap(.address: UIntNative, .length: UIntNative) -> (.status: Int32) : ExternFunction

_memory_map_anonymous(.length: UIntNative) -> (.address: UIntNative) := {
    -- MAP_PRIVATE | MAP_ANONYMOUS is 34 on Linux and 4098 on macOS.
    -- The unsupported form fails with MAP_FAILED, then the other is tried.
    address = _memory_mmap(.hint = 0, .length = length, .protection = 3, .flags = 34, .file_descriptor = -1, .offset = 0).address
    if address + 1 == 0 {
        address = _memory_mmap(.hint = 0, .length = length, .protection = 3, .flags = 4098, .file_descriptor = -1, .offset = 0).address
    }
}

_memory_map_aligned(
    .size: UIntNative,
    .alignment: UIntNative,
    .page_size: UIntNative,
) -> (.result: Errable#(.t: UIntNative, .reasons: (..out_of_memory))) := {
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
    result = ..ok address
}

map_pages(.self: $&Memory, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    physical_size ::= page_allocator_round_up(.size = size, .alignment = self&._page_size).rounded
    mapped ::= _memory_map_aligned(.size = size, .alignment = alignment, .page_size = self&._page_size)
    match mapped {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok address {
            deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
            allocation ::= establish_allocation(.storage = address, .size = physical_size, .alignment = alignment, .deallocator = deallocator)
            result = ..ok ~allocation
        }
    }
}

deallocate(.self: $&Memory, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    physical_size ::= page_allocator_round_up(.size = size, .alignment = self&._page_size).rounded
    if _memory_munmap(.address = data.address, .length = physical_size).status != 0 { abort }
}
Memory implements Deallocator
