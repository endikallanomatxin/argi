PageAllocator : Type = (
    --
    -- Baseline page-sized allocator.
    --
    -- For 0.1 this keeps the public allocator shape simple by using libc to
    -- obtain page-aligned, page-sized heap allocations. A future platform
    -- layer can replace the internals with direct OS page mapping without
    -- changing users of `Allocator`.
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

init(
    .p: $&PageAllocator,
) -> () := {
    p&.page_size = getpagesize().size
    if p&.page_size == 0 {
        p&.page_size = 4096
    }
}

allocate(
    .self: $&PageAllocator,
    .size: UIntNative,
    .alignment: UIntNative,
) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    _require_allocation_alignment(.alignment = alignment)
    page_size ::= page_allocator_page_size(.self = self).size
    physical_alignment ::= page_size
    if physical_alignment < alignment { physical_alignment = alignment }
    if physical_alignment == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    aligned_size ::= page_allocator_round_up(.size = size, .alignment = physical_alignment).rounded
    if aligned_size < size {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    address ::= aligned_alloc(.alignment = physical_alignment, .size = aligned_size).address
    if address == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = address, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(
    .self: $&PageAllocator,
    .data: RawPointer#(.t: UInt8),
    .size: UIntNative,
    .alignment: UIntNative,
) -> () := {
    free(.address = data.address)
}

PageAllocator implements Allocator
PageAllocator implements Deallocator
