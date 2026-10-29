PageAllocator := (
    .memory    : $&Memory
    .page_size : UIntNative
)

PageAllocatorInitArgs: Type = (.memory: $&Memory)

implement Init#(PageAllocator, PageAllocatorInitArgs) (
    .Result : Type = PageAllocator

    .init = PageAllocatorInitArgs -> (.result: Result) {
        _init_memory ::= memory
        result = (.memory = _init_memory, .page_size = _init_memory&._page_size)
    }
)

page_allocator_page_size := (.self: $&PageAllocator) -> (.size: UIntNative) {
    size = self&.page_size
}

page_allocator_round_up := (.size: UIntNative, .alignment: UIntNative) -> (.rounded: UIntNative) {
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

implement Allocator#(PageAllocator) (
    .allocate = (
        .self         : $&PageAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(Allocation, (..out_of_memory))) {
        assume error_tracer

        mapped ::= map_pages(self&.memory, .size = size, .alignment = alignment)

        match mapped {
            ..error _ { result = ..error(.reason = ..out_of_memory) }
            ..ok ~payload {
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
)
