TrackingAllocator : Type = (
    .backing: $&PageAllocator
    .allocations: UIntNative
    .deallocations: UIntNative
)

allocate(.self: $&TrackingAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    allocated ::= allocate(.self = self&.backing, .size = size, .alignment = alignment)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            original ::= ~payload
            self&.allocations = self&.allocations + 1
            -- Tracking delegates release to the same backing allocator.
            original.deallocator = to_virtual#(.abstract: Deallocator)(.value = self)
            result = ..ok ~original
        }
    }
}

deallocate(.self: $&TrackingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    deallocate(.self = self&.backing&.memory, .data = data, .size = size, .alignment = alignment)
}
TrackingAllocator implements Allocator
TrackingAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32) := {
    tracker :: TrackingAllocator = (.backing = system.page_allocator, .allocations = 0, .deallocations = 0)
    allocator_storage ::= GeneralPurposeAllocator(.allocator = $&tracker)
    assume allocator ::= $&allocator_storage
    if tracker.allocations != 0 { status_code = 1
        return }
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: UInt8)(.capacity = 16))
    push#(.t: UInt8)(.self = $&array, .value = 65)
    deinit#(.t: UInt8)(.self = $&array)
    if tracker.allocations == 0 or tracker.allocations != tracker.deallocations { status_code = 2
        return }
    arena :: ArenaAllocator
    initialized ::= ArenaAllocator(.allocator = $&allocator_storage, .block_size = 64)
    match initialized {
        ..ok ~constructed_value { arena = ~constructed_value }
        ..error _ { status_code = 3
        return }
    }
    previous ::= tracker.allocations
    reserved ::= allocate(.self = $&arena, .size = 48, .alignment = 32)
    match reserved {
        ..error _ { status_code = 4
            return }
        ..ok ~ payload {
            storage ::= ~payload
            if storage.data.address % 32 != 0 { status_code = 5
                return }
            deinit(.self = $&storage)
        }
    }
    if tracker.allocations <= previous { status_code = 6
        return }
    reset(.self = $&arena)
    deinit(.self = $&arena)
    if tracker.allocations != tracker.deallocations { status_code = 7
        return }
    status_code = 0
}
