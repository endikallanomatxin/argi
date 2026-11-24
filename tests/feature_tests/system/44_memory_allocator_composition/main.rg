TrackingAllocator := (
    .backing       : $&PageAllocator
    .allocations   : UIntNative
    .deallocations : UIntNative
)

main := (.system: System) -> (.status_code: Int32) {

    page :: PageAllocator = PageAllocator(.memory = system.memory)
    tracker :: TrackingAllocator = (
        .backing       = $&page
        .allocations   = 0
        .deallocations = 0
    )
    tracker_virtual ::= Virtual#(Allocator)($&tracker)
    allocator_storage ::= GeneralPurposeAllocator(.allocator = tracker_virtual)
    allocator_concrete := $&allocator_storage
    virtual_allocator ::= Virtual#(Allocator)(allocator_concrete)
    assume allocator := virtual_allocator
    if tracker.allocations != 0 {
        status_code = 1
        return
    }
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UInt8)(.capacity = 16))
    push(.self = $&array, .value = 65, .allocator = allocator)
    deinit(.self = $&array)
    if tracker.allocations == 0 or tracker.allocations != tracker.deallocations {
        status_code = 2
        return
    }
    arena :: ArenaAllocator
    initialized ::= ArenaAllocator(.allocator = allocator, .block_size = 64)
    match initialized {
        ..ok ~constructed_value { arena = ~constructed_value }
        ..error _ {
            status_code = 3
            return
        }
    }
    previous ::= tracker.allocations
    reserved ::= allocate_bytes(.self = $&arena, .size = 48, .alignment = 32)
    match reserved {
        ..error _ {
            status_code = 4
            return
        }
        ..ok ~payload {
            storage ::= ~payload
            if storage.data.address % 32 != 0 {
                status_code = 5
                return
            }
            deinit(.self = $&storage)
        }
    }
    if tracker.allocations <= previous {
        status_code = 6
        return
    }
    reset(.self = $&arena)
    deinit(.self = $&arena)
    if tracker.allocations != tracker.deallocations {
        status_code = 7
        return
    }
    status_code = 0
}

implement Allocator#(TrackingAllocator) (
    .allocate = (.self: $&TrackingAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) {

        allocated ::= acquire_page_storage(
            .memory = self&.backing&.memory, .size = size, .alignment = alignment
        )
        match allocated {
            ..error _ { result = ..error(.reason = ..out_of_memory) }
            ..ok ~payload {
                storage ::= ~payload
                release ::= Virtual#(Deallocator)(self)
                original ::= establish_allocation(
                    .storage = ~storage, .size = size, .alignment = alignment, .deallocator = release
                )
                self&.allocations = self&.allocations + 1
                result = ..ok ~original
            }
        }
    }
)

implement Deallocator#($&TrackingAllocator) (
    .deallocate = (
        .self      : $&TrackingAllocator,
        .request: Deallocation
    ) -> () {
        self&.deallocations = self&.deallocations + 1
        Deallocator#(
        ).deallocate(
            .self = self&.backing&.memory, .request = ~request
        )
    }
)
