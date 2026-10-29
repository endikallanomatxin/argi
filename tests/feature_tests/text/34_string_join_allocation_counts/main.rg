RecordingAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
    .last_size     : UIntNative                 = 0
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    allocator :: RecordingAllocator = (.ffi = system.ffi)
    parts: [3]StringView = ("ab", "", "c")
    output ::= unwrap_or_abort(
        .value = join(.parts = view(.self = &parts), .separator = "-", .allocator = $&allocator)
    )
    if allocator.allocations != 1 or allocator.last_size != 6 { abort }
    if [
        is(
            .value   = bytes_get(.view = &output, .index = byte_length(&output).count)
            .variant = ..error
        )
        == false
    ] { abort }
    deinit(.self = $&output)
    if allocator.deallocations != 1 { abort }
    empty: [0]StringView = ()
    output_empty ::= unwrap_or_abort(
        .value = join(.parts = view(.self = &empty), .separator = ",", .allocator = $&allocator)
    )
    if allocator.allocations != 2 or allocator.last_size != 1 { abort }
    deinit(.self = $&output_empty)
    if allocator.deallocations != 2 { abort }
}

implement Allocator#(RecordingAllocator) (
    .allocate = (
        .self         : $&RecordingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative                         = 1,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) {
        assume error_tracer

        self&.allocations = self&.allocations + 1
        self&.last_size = size
        storage ::= malloc(.size = size, .ffi = self&.ffi)
        if storage | convert#(.to: UIntNative)(_) == 0 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        deallocator :: Virtual#(.contract: Deallocator) = to_virtual#(.contract: Deallocator)(
            .value = self
        )
        allocation ::= trusted_establish_allocation(
            .storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator
        )
        result = ..ok ~allocation
    }
)

implement Deallocator#(RecordingAllocator) (
    .deallocate = (
        .self      : $&RecordingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () {
        self&.deallocations = self&.deallocations + 1
        free(.address = data.address, .ffi = self&.ffi)
    }
)
