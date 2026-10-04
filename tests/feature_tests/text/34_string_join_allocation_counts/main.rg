RecordingAllocator: Type = (
    .ffi           : $&ForeignFunctionInterface
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
    .last_size     : UIntNative                 = 0
)

allocate(
        .self      : $&RecordingAllocator,
        .size      : UIntNative,
        .alignment : UIntNative            = 1
    ) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) := {
    self&.allocations = self&.allocations + 1
    self&.last_size = size
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    if UIntNative(.value = storage) == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(
        .value = self
    )
    allocation ::= trusted_establish_allocation(
        .storage     = storage
        .size        = size
        .alignment   = alignment
        .deallocator = deallocator
    )
    result = ..ok ~allocation
}

deallocate(
        .self      : $&RecordingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.address = data.address, .ffi = self&.ffi)
}

RecordingAllocator implements Allocator
RecordingAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator :: RecordingAllocator = (.ffi = system.ffi)
    parts: [3]StringView = ("ab", "", "c")
    output ::= unwrap_or_abort(
        .value = join(
            .parts     = array_view_ro(.array = &parts).view
            .separator = "-"
            .allocator = $&allocator
        )
    )
    if allocator.allocations != 1 or allocator.last_size != 6 { abort }
    if bytes_get(.string = &output, .index = output.length).byte != 0 { abort }
    deinit(.self = $&output, .allocator = $&allocator)
    if allocator.deallocations != 1 { abort }
    empty: [0]StringView = ()
    output_empty ::= unwrap_or_abort(
        .value = join(
            .parts     = array_view_ro(.array = &empty).view
            .separator = ","
            .allocator = $&allocator
        )
    )
    if allocator.allocations != 2 or allocator.last_size != 1 { abort }
    deinit(.self = $&output_empty, .allocator = $&allocator)
    if allocator.deallocations != 2 { abort }
}
