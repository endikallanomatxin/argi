PageAllocator : Type = (
    --
    -- Page-backed allocator for the POSIX runtime. Over-aligned
    -- requests map extra pages and release the unused prefix and suffix.
    --
    .page_size : UIntNative = 0
)

page_allocator_page_size(
    .self: $&PageAllocator,
) -> (.size: UIntNative) := {
    cached ::= self&.page_size
    if cached == 0 {
        detected ::= getpagesize().size
        if detected == 0 {
            detected = 4096
        }
        self&.page_size = detected
        cached = detected
    }
    size = cached
}

page_allocator_round_up(
    .size: UIntNative,
    .alignment: UIntNative,
) -> (.rounded: UIntNative) := {
    rounded = size
    if rounded == 0 {
        rounded = alignment
        return
    }

    one :: UIntNative = 1
    blocks :: UIntNative = rounded / alignment
    if blocks * alignment != rounded {
        next_blocks :: UIntNative = blocks + one
        rounded = next_blocks * alignment
    }
}

_page_allocator_map_anonymous(.length: UIntNative) -> (.address: UIntNative) := {
    -- MAP_PRIVATE | MAP_ANONYMOUS is 34 on Linux and 4098 on macOS.
    -- The unsupported form fails with MAP_FAILED, then the other is tried.
    address = mmap(.hint = 0, .length = length, .protection = 3, .flags = 34, .file_descriptor = -1, .offset = 0).address
    if address + 1 == 0 {
        address = mmap(.hint = 0, .length = length, .protection = 3, .flags = 4098, .file_descriptor = -1, .offset = 0).address
    }
}

init(
    .p: $&PageAllocator,
) -> () := {
    p&.page_size = getpagesize().size
    if p&.page_size == 0 {
        p&.page_size = 4096
    }
}

_page_allocator_map_aligned(
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
    mapped_address ::= _page_allocator_map_anonymous(.length = request_size).address
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
            if munmap(.address = mapped_address, .length = padding).status != 0 { abort }
        }
        mapped_end ::= mapped_address + request_size
        used_end ::= address + mapped_size
        if used_end < mapped_end {
            if munmap(.address = used_end, .length = mapped_end - used_end).status != 0 { abort }
        }
    }
    result = ..ok address
}

allocate(
    .self: $&PageAllocator,
    .size: UIntNative,
    .alignment: UIntNative,
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    mapped ::= _page_allocator_map_aligned(.size = size, .alignment = alignment, .page_size = page_allocator_page_size(.self = self).size)
    match mapped {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok address {
            deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
            allocation ::= establish_allocation(.storage = address, .size = size, .alignment = alignment, .deallocator = deallocator)
            result = ..ok ~allocation
        }
    }
}

deallocate(
    .self: $&PageAllocator,
    .data: RawPointer#(.t: UInt8),
    .size: UIntNative,
    .alignment: UIntNative,
) -> () := {
    mapped_size ::= page_allocator_round_up(.size = size, .alignment = page_allocator_page_size(.self = self).size).rounded
    if munmap(.address = data.address, .length = mapped_size).status != 0 { abort }
}

PageAllocator implements Allocator
PageAllocator implements Deallocator
