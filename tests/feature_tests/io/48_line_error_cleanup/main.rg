RecordingAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
    .fail_after    : UIntNative                 = 999
)

Source := (.text: StringView, .position: UIntNative = 0, .fail_after: UIntNative = 999)

implement Reader#(Source) (
    .read_byte = (.self: $&Source, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(ReadByte, (..stream_read_failed))
    ) {
        assume error_tracer

        if self&.position == self&.fail_after {
            result = ..error(.reason = ..stream_read_failed)
            return
        }
        if self&.position == byte_length(&self&.text).count {
            result = ..ok ..end
            return
        }

        byte ::= unwrap_or_abort(.value = bytes_get(&self&.text, self&.position))
        self&.position = self&.position + 1
        result = ..ok ..ok byte
    }
)

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    allocator ::= RecordingAllocator(.ffi = system.ffi)
    failed_reader ::= Source(.text = "abc", .fail_after = 1)
    match read_line(.allocator = $&allocator, .reader = $&failed_reader) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    if allocator.allocations != 1 or allocator.deallocations != 1 { abort }

    allocator.fail_after = 2
    growing_reader ::= Source(.text = "abcdefghijklmnopq\n")
    match read_line(.allocator = $&allocator, .reader = $&growing_reader) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if allocator.allocations != 2 or allocator.deallocations != 2 { abort }

    allocator.fail_after = 999
    eof_reader ::= Source(.text = "")
    match read_line(.allocator = $&allocator, .reader = $&eof_reader)!!! {
        ..end {}
        ..ok ~_ { abort }
    }
    if allocator.allocations != 3 or allocator.deallocations != 3 { abort }
    status_code = 0
}

implement Allocator#(RecordingAllocator) (
    .allocate = (
        .self         : $&RecordingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative              = 1,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(Allocation, (..out_of_memory))) {
        assume error_tracer

        if self&.allocations == self&.fail_after {
            result = ..error(.reason = ..out_of_memory)
            return
        }

        storage ::= malloc(.size = size, .ffi = self&.ffi)
        if storage | convert#(.to: UIntNative)(_) == 0 {
            result = ..error(.reason = ..out_of_memory)
            return
        }
        self&.allocations = self&.allocations + 1
        deallocator: Virtual#(Deallocator) = to_virtual#(.contract: Deallocator)(
            .value = self
        )
        result = ..ok ~trusted_establish_allocation(
            .storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator
        )
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
