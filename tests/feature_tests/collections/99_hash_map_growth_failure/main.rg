RecordingAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .fail          : Bool                       = false
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator :: RecordingAllocator = (.ffi = system.ffi)
    map ::= unwrap_or_abort(
        .value = HashMap<.key: Int32, .value: Int32, .policy: StandardHashPolicy>(
            .policy = StandardHashPolicy(), .allocator = $&allocator
        )
    )
    index :: Int32 = 0
    while index < 4 {
        unwrap_or_abort(
            .value = put(.self = $&map, .key = index, .value = index, .allocator = $&allocator)
        )
        index = index + 1
    }
    allocator.fail = true
    match put(.self = $&map, .key = 4, .value = 4, .allocator = $&allocator).result {
        ..ok _ { abort }
        ..error ~err { if err.reason != ..out_of_memory { abort } }
    }
    if length(.self = &map).count != 4 or capacity(.self = &map).count != 8 { abort }
    index = 0
    while index < 4 {
        match get(.self = &map, .key = &index).result {
            ..none { abort }
            ..some entry { if entry.value != index { abort } }
        }
        index = index + 1
    }
    unwrap_or_abort(
        .value = put(.self = $&map, .key = 0, .value = 99, .allocator = $&allocator)
    )
    if allocator.allocations != 2 or allocator.deallocations != 0 { abort }
    allocator.fail = false
    unwrap_or_abort(.value = put(.self = $&map, .key = 4, .value = 4, .allocator = $&allocator))
    if allocator.allocations != 4 or allocator.deallocations != 2 { abort }
    deinit(.self = $&map)
    if allocator.deallocations != 4 { abort }
}

implement Allocator<RecordingAllocator> (
    .allocate = (.self: $&RecordingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result: Errable<.t: Allocation, .reasons: (..out_of_memory)>
    ) {
        if self&.fail {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        self&.allocations = self&.allocations + 1
        storage ::= malloc(.size = size, .ffi = self&.ffi)
        if storage | convert<.to: UIntNative>(_) == 0 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        deallocator :: Virtual<.contract: Deallocator> = to_virtual<.contract: Deallocator>(
            .value = self
        )
        allocation ::= trusted_establish_allocation(
            .storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator
        )
        result = ..ok ~allocation
    }
)

implement Deallocator<RecordingAllocator> (
    .deallocate = (
        .self      : $&RecordingAllocator,
        .data      : RawPointer<.t: UInt8>,
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        self&.deallocations = self&.deallocations + 1
        free(.address = data.address, .ffi = self&.ffi)
    }
)
