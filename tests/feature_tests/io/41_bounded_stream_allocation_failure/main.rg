RecordingAllocator: Type = (
    .ffi           : $&ForeignFunctionInterface
    .fail_at       : UIntNative                 = 0
    .attempts      : UIntNative                 = 0
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
)

allocate(
        .self      : $&RecordingAllocator,
        .size      : UIntNative,
        .alignment : UIntNative            = 1
    ) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) := {
    self&.attempts = self&.attempts + 1
    if self&.attempts == self&.fail_at {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    self&.allocations = self&.allocations + 1
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

FaultReader: Type = (.position: UIntNative = 0, .calls: UIntNative = 0, .fail_at: UIntNative = 0)

FaultReader implements BlockReader

read_block(
        .self   : $&FaultReader,
        .buffer : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(.t: UIntNative, .reasons: (..stream_read_failed))
    ) := {
    self&.calls = self&.calls + 1
    if self&.calls == self&.fail_at {
        result = ..error(.reason = ..stream_read_failed)
        return
    }
    if self&.position == 8 {
        result = ..ok 0
        return
    }
    slot ::= unwrap_or_abort(.value = get_rw_ref(.self = $&buffer, .index = 0))
    slot&= 65
    self&.position = self&.position + 1
    result = ..ok 1
}

run_main(.system: System) -> !Void = ..ok Void() := {
    allocator :: RecordingAllocator = (.ffi = system.ffi, .fail_at = 1)
    source :: FaultReader = FaultReader()
    scratch :: [2]UInt8 = (0, 0)
    match read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 8
        .allocator = $&allocator
    ) {
        ..ok ~owner {
            deinit(.self = $&owner, .allocator = $&allocator)
            abort
        }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if source.calls != 0 or allocator.allocations != allocator.deallocations { abort }
    allocator.fail_at = allocator.attempts + 2
    match read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 8
        .allocator = $&allocator
    ) {
        ..ok ~owner {
            deinit(.self = $&owner, .allocator = $&allocator)
            abort
        }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    -- The initial chunk remains the only consumed data when growth fails.
    if source.calls != 1 or source.position != 1 or allocator.allocations != allocator.deallocations {
        abort
    }
    source.calls = 0
    source.position = 0
    source.fail_at = 3
    allocator.fail_at = 0
    match read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 8
        .allocator = $&allocator
    ) {
        ..ok ~owner {
            deinit(.self = $&owner, .allocator = $&allocator)
            abort
        }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    if allocator.allocations != allocator.deallocations { abort }
    source.calls = 0
    source.position = 0
    source.fail_at = 0
    match read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 2
        .allocator = $&allocator
    ) {
        ..ok ~owner {
            deinit(.self = $&owner, .allocator = $&allocator)
            abort
        }
        ..error error { if error.reason != ..size_limit_exceeded { abort } }
    }
    if source.position != 3 or allocator.allocations != allocator.deallocations { abort }
    source.position = 0
    maximum :: UIntNative = 0
    native_bytes ::= size_of(.type = UIntNative)
    index :: UIntNative = 0
    while index < native_bytes {
        maximum = maximum * 256 + 255
        index = index + 1
    }
    attempts ::= allocator.attempts
    calls ::= source.calls
    match read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = maximum
        .allocator = $&allocator
    ) {
        ..ok ~owner {
            deinit(.self = $&owner, .allocator = $&allocator)
            abort
        }
        ..error error { if error.reason != ..size_overflow { abort } }
    }
    if allocator.attempts != attempts or source.calls != calls { abort }
    owned ::= read_all_limited(
        .self      = $&source
        .buffer    = view(.array = $&scratch)
        .limit     = 8
        .allocator = $&allocator
    )!
    if owned.length != 8 or capacity(.self = &owned).value > 8 { abort }
    deinit(.self = $&owned, .allocator = $&allocator)
    if allocator.allocations != allocator.deallocations { abort }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
