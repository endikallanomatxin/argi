RecordingAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
    .last_size     : UIntNative                 = 0
    .fail          : Bool                       = false
)

expect_formatted := #(.t: Type: Int) (
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

    allocator ::= RecordingAllocator(.ffi = system.ffi)
    int80: Int8 = -128
    expect_formatted(.allocator = $&allocator, .value = int80, .expected = "-128")
    int81: Int8 = 0
    expect_formatted(.allocator = $&allocator, .value = int81, .expected = "0")
    int82: Int8 = 127
    expect_formatted(.allocator = $&allocator, .value = int82, .expected = "127")
    int160: Int16 = -32768
    expect_formatted(.allocator = $&allocator, .value = int160, .expected = "-32768")
    int161: Int16 = 0
    expect_formatted(.allocator = $&allocator, .value = int161, .expected = "0")
    int162: Int16 = 32767
    expect_formatted(.allocator = $&allocator, .value = int162, .expected = "32767")
    int320: Int32 = -2147483648
    expect_formatted(.allocator = $&allocator, .value = int320, .expected = "-2147483648")
    int321: Int32 = 0
    expect_formatted(.allocator = $&allocator, .value = int321, .expected = "0")
    int322: Int32 = 2147483647
    expect_formatted(.allocator = $&allocator, .value = int322, .expected = "2147483647")
    int640: Int64 = -9223372036854775808
    expect_formatted(
        .allocator = $&allocator, .value = int640, .expected = "-9223372036854775808"
    )
    int641: Int64 = 0
    expect_formatted(.allocator = $&allocator, .value = int641, .expected = "0")
    int642: Int64 = 9223372036854775807
    expect_formatted(
        .allocator = $&allocator, .value = int642, .expected = "9223372036854775807"
    )
    uint80: UInt8 = 0
    expect_formatted(.allocator = $&allocator, .value = uint80, .expected = "0")
    uint81: UInt8 = 255
    expect_formatted(.allocator = $&allocator, .value = uint81, .expected = "255")
    uint160: UInt16 = 0
    expect_formatted(.allocator = $&allocator, .value = uint160, .expected = "0")
    uint161: UInt16 = 65535
    expect_formatted(.allocator = $&allocator, .value = uint161, .expected = "65535")
    uint320: UInt32 = 0
    expect_formatted(.allocator = $&allocator, .value = uint320, .expected = "0")
    uint321: UInt32 = 4294967295
    expect_formatted(.allocator = $&allocator, .value = uint321, .expected = "4294967295")
    uint640: UInt64 = 0
    expect_formatted(.allocator = $&allocator, .value = uint640, .expected = "0")
    uint641: UInt64 = 18446744073709551615
    expect_formatted(
        .allocator = $&allocator, .value = uint641, .expected = "18446744073709551615"
    )
    uintnative0: UIntNative = 0
    expect_formatted(.allocator = $&allocator, .value = uintnative0, .expected = "0")
    uintnative1: UIntNative = 18446744073709551615
    expect_formatted(
        .allocator = $&allocator, .value = uintnative1, .expected = "18446744073709551615"
    )
    -- Reserved output must remain appendable even when allocations fail.
    output ::= unwrap_or_abort(
        .value = string_with_capacity(.capacity = 64, .allocator = $&allocator)
    )
    before ::= allocator.allocations
    allocator.fail = true
    minimum: Int64 = -9223372036854775808
    maximum: UInt64 = 18446744073709551615
    unwrap_or_abort(
        .value = format_into(.out = $&output, .value = minimum, .allocator = $&allocator)
    )
    unwrap_or_abort(
        .value = format_into(.out = $&output, .value = maximum, .allocator = $&allocator)
    )
    if view(.self = &output).view != "-922337203685477580818446744073709551615" { abort }
    if allocator.allocations != before { abort }
    deinit(.self = $&output)

    failed ::= format(.value = 12345, .allocator = $&allocator)
    if is(.value = failed, .variant = ..error) {
        if failed ..error.reason != ..out_of_memory { abort }
    } else {
        abort
    }
    if allocator.allocations != before + 1 { abort }
    if allocator.deallocations != before { abort }
}

implement Allocator#(RecordingAllocator) (
    .allocate = (.self: $&RecordingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result : Errable#(.t: Allocation, .reasons: (..out_of_memory))
    ) {

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
        deallocator :: Virtual#(Deallocator) = to_virtual#(.contract: Deallocator)(
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
