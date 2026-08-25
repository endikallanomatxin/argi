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
) -> (.data: $&UInt8) := {
    page_size ::= page_allocator_page_size(.self = self).size
    aligned_size ::= page_allocator_round_up(.size = size, .alignment = page_size).rounded
    raw ::= aligned_alloc(.alignment = page_size, .size = aligned_size)
    data = establish_fresh_reference#(.t: UInt8)(
        .raw = raw_pointer#(.t: UInt8)(.address = cast#(.to: UIntNative)(.value = raw)),
    ).reference
}

deallocate(
    .self: $&PageAllocator,
    .data: $&UInt8,
    .size: UIntNative,
) -> () := {
    free(.pointer = cast#(.to: &Any)(.value = cast#(.to: UIntNative)(.value = data)))
}

PageAllocator implements Allocator
