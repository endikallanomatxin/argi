PageAllocator : Type = (
    .memory: $&Memory
    .page_size: UIntNative
)

init(.p: $&PageAllocator, .memory: $&Memory) -> () := {
    p&.memory = memory
    p&.page_size = memory&._page_size
}

page_allocator_page_size(.self: $&PageAllocator) -> (.size: UIntNative) := {
    size = self&.page_size
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

allocate(.self: $&PageAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    mapped ::= map_pages(.self = self&.memory, .size = size, .alignment = alignment)
    match mapped {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            allocation ::= ~payload
            allocation.size = size
            -- Page padding is not part of the range granted to the caller.
            -- Memory rounds this extent back to pages during physical cleanup.
            allocation._storage_size = size
            allocation._release_size = size
            result = ..ok ~allocation
        }
    }
}

PageAllocator implements Allocator
