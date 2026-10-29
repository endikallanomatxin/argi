RecordingAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
    .last_size     : UIntNative                 = 0
    .fail          : Bool                       = false
)

expect_formatted := #(.t: Type: Float) (
    .allocator: $&RecordingAllocator, .value: t, .expected: StringView
) -> () {
    before ::= allocator&.allocations
    freed ::= allocator&.deallocations
    output ::= unwrap_or_abort(.value = format(.value = value, .allocator = allocator))
    if view(.self = &output).view != expected { abort }
    if [
        allocator&.allocations != before + 1
        or allocator&.last_size != byte_length(&expected).count + 1
    ] {
        abort
    }
    deinit(.self = $&output)
    if allocator&.deallocations != freed + 1 { abort }
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume system
    allocator ::= RecordingAllocator(.ffi = system.ffi)
    value16 :: Float16 = 0.1
    expect_formatted(.allocator = $&allocator, .value = value16, .expected = "0.1")
    value16 = 65504.0
    expect_formatted(.allocator = $&allocator, .value = value16, .expected = "65500.0")
    value32 :: Float32 = 0.1
    expect_formatted(.allocator = $&allocator, .value = value32, .expected = "0.1")
    value32 = 1.401298464324817e-45
    expect_formatted(.allocator = $&allocator, .value = value32, .expected = "1e-45")
    value64 :: Float64 = 1.7976931348623157e308
    expect_formatted(
        .allocator = $&allocator, .value = value64, .expected = "1.7976931348623157e308"
    )
    value64 = -5e-324
    expect_formatted(.allocator = $&allocator, .value = value64, .expected = "-5e-324")
    value64 = -0.0
    expect_formatted(.allocator = $&allocator, .value = value64, .expected = "-0.0")
    bits: UInt64 = 9218868437227405312
    value64 = trusted_reinterpret_reference#(.from: UInt64, .to: Float64)(
        .base = &bits
    ).reference&
    expect_formatted(.allocator = $&allocator, .value = value64, .expected = "inf")
    nan_bits: UInt64 = 9221120237041090561
    value64 = trusted_reinterpret_reference#(.from: UInt64, .to: Float64)(
        .base = &nan_bits
    ).reference&
    expect_formatted(.allocator = $&allocator, .value = value64, .expected = "nan")

    output ::= unwrap_or_abort(
        .value = string_with_capacity(.capacity = 64, .allocator = $&allocator)
    )
    before ::= allocator.allocations
    allocator.fail = true
    value64 = 1.7976931348623157e308
    unwrap_or_abort(
        .value = format_into(.out = $&output, .value = value64, .allocator = $&allocator)
    )
    value64 = -5e-324
    unwrap_or_abort(
        .value = format_into(.out = $&output, .value = value64, .allocator = $&allocator)
    )
    if view(.self = &output).view != "1.7976931348623157e308-5e-324" { abort }
    if allocator.allocations != before { abort }
    deinit(.self = $&output)
    value64 = 0.1
    failed ::= format(.value = value64, .allocator = $&allocator)
    if is(.value = failed, .variant = ..error) {
        if failed ..error.reason != ..out_of_memory { abort }
    } else {
        abort
    }
    if allocator.allocations != before + 1 or allocator.deallocations != before { abort }
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
        if self&.fail {
            result = ..error(.reason = ..out_of_memory)
            return
        }
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
