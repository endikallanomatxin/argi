semver := import ("semver")

RecordingAllocator := (
    .ffi           : $&ForeignFunctionInterface
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
    .last_size     : UIntNative                 = 0
    .fail          : Bool                       = false
)

RecordingWriter := (
    .expected      : StringView
    .count         : UIntNative = 0
    .flush_calls   : UIntNative = 0
    .fail_at       : UIntNative = 999
    .flush_failure : Bool       = false
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= RecordingAllocator(.ffi = system.ffi)
    version ::= unwrap_or_abort(.value = semver.parse(.text = "1.2.3-alpha+001")).result
    output ::= unwrap_or_abort(
        .value = format(.value = &version, .allocator = $&allocator)
    ).result
    if view(.self = &output).view != "1.2.3-alpha+001" { abort }
    if allocator.allocations != 1 or allocator.last_size != 16 { abort }
    deinit(.self = $&output)
    buffer ::= unwrap_or_abort(
        .value = string_with_capacity(.capacity = 64, .allocator = $&allocator)
    ).result
    allocator.fail = true
    unwrap_or_abort(.value = push_view(.self = $&buffer, .view = "v", .allocator = $&allocator))
    unwrap_or_abort(
        .value = format_into(.out = $&buffer, .value = &version, .allocator = $&allocator)
    )
    if view(.self = &buffer).view != "v1.2.3-alpha+001" { abort }
    if allocator.allocations != 2 { abort }
    match format(.value = &version, .allocator = $&allocator) {
        ..error _ {} ..ok ~text {
            deinit(.self = $&text)
            abort
        }
    }
    deinit(.self = $&buffer)
    if allocator.deallocations != 2 { abort }
    counting ::= CountingDestination()
    count ::= write(.self = $&counting, .value = &version).result
    if count != 15 or counting.bytes != 15 { abort }
    writer ::= RecordingWriter(.expected = "1.2.3-alpha+001")
    unwrap_or_abort(.value = write(.self = $&writer, .value = &version))
    if writer.count != 15 or writer.flush_calls != 0 { abort }
    writer.count = 0
    writer.fail_at = 2
    match write(.self = $&writer, .value = &version) {
        ..error error { if error.reason != ..stream_write_failed { abort } } ..ok _ { abort }
    }
    writer.count = 0
    writer.flush_failure = true
    match write(.self = $&writer, .value = &version) {
        ..error error { if error.reason != ..stream_flush_failed { abort } } ..ok _ { abort }
    }
}

implement Writer#(RecordingWriter) (
    .write_byte = (
        .self: $&RecordingWriter, .byte: UInt8, .error_tracer: $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        if self&.count == self&.fail_at {
            if self&.flush_failure {
                result = ..error(.reason = ..stream_flush_failed)
            } else {
                result = ..error(.reason = ..stream_write_failed)
            }
            return
        }
        if self&.count >= byte_length(&self&.expected).count { abort }
        if [
            byte
            != unwrap_or_abort(
                .value = bytes_get(.view = &self&.expected, .index = self&.count)
            )
        ] { abort }
        self&.count = self&.count + 1
        result = ..ok Void()
    }

    .flush = (.self: $&RecordingWriter, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {
        assume error_tracer

        self&.flush_calls = self&.flush_calls + 1
        result = ..ok Void()
    }
)

implement Allocator#(RecordingAllocator) (
    .allocate = (
        .self         : $&RecordingAllocator,
        .size         : UIntNative,
        .alignment    : UIntNative              = 1,
        .error_tracer : $&Virtual#(ErrorTracer)
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

CountingDestination := (.bytes: UIntNative = 0)

implement WriteValue#(CountingDestination, StringView) (
    .Result      : Type = UIntNative
    .write_value = (
        .self: $&CountingDestination, .value: StringView, .error_tracer: $&Virtual#(ErrorTracer)
    ) -> (.result: UIntNative) {
        assume error_tracer
        self&.bytes = self&.bytes + byte_length(&value).count
        result = byte_length(&value).count
    }
)
