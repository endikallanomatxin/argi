FaultReader := (
    .position : UIntNative = 0,
    .calls    : UIntNative = 0,
    .fail_at  : UIntNative = 0
)

implement BlockReader#(FaultReader) (
    .read_block = (
        .self         : $&FaultReader,
        .buffer       : MutableArrayView#(.t: UInt8),
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(.t: UIntNative, .reasons: (..stream_read_failed))) {
        assume error_tracer

        self&.calls = self&.calls + 1
        if self&.calls == self&.fail_at {
            result = ..error(.reason = ..stream_read_failed)
            return
        }
        if self&.position == 8 {
            result = ..ok 0
            return
        }
        slot ::= unwrap_or_abort(.value = get_mutable_reference(.self = $&buffer, .index = 0))
        slot&= 65
        self&.position = self&.position + 1
        result = ..ok 1
    }
)

FaultWriter := (
    .count   : UIntNative = 0,
    .calls   : UIntNative = 0,
    .fail_at : UIntNative = 0,
    .stalled : Bool       = false
)

implement BlockWriter#(FaultWriter) (
    .write_block = (
        .self         : $&FaultWriter,
        .buffer       : ArrayView#(.t: UInt8),
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (
        .result : Errable#(
            .t: UIntNative, .reasons: (..stream_write_failed, ..stream_flush_failed)
        )
    ) {
        assume error_tracer

        self&.calls = self&.calls + 1
        if self&.calls == self&.fail_at {
            result = ..error(.reason = ..stream_flush_failed)
            return
        }
        if self&.stalled {
            result = ..ok 0
            return
        }
        self&.count = self&.count + 1
        result = ..ok 1
    }
)

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    scratch :: [2]UInt8 = (0, 0)
    source :: FaultReader = FaultReader(.fail_at = 3)
    sink :: FaultWriter = FaultWriter()
    match copy_stream_limited(
        .reader = $&source, .writer = $&sink, .buffer = view(.self = $&scratch), .limit = 8
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    if source.position != 2 or sink.count != 2 { abort }
    source.position = 0
    source.calls = 0
    source.fail_at = 0
    sink.calls = 0
    sink.count = 0
    sink.fail_at = 3
    match copy_stream_limited(
        .reader = $&source, .writer = $&sink, .buffer = view(.self = $&scratch), .limit = 8
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_flush_failed { abort } }
    }
    if source.position != 3 or sink.count != 2 { abort }
    sink.stalled = true
    sink.fail_at = 0
    match copy_stream_limited(
        .reader = $&source, .writer = $&sink, .buffer = view(.self = $&scratch), .limit = 8
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_write_failed { abort } }
    }
    if source.position != 4 or sink.count != 2 { abort }
    source.position = 0
    source.calls = 0
    source.fail_at = 3
    match read_all_limited(
        .self = $&source, .buffer = view(.self = $&scratch), .limit = 8, .allocator = allocator
    ) {
        ..ok ~owner {
            deinit(.self = $&owner)
            abort
        }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    if source.position != 2 { abort }
    empty :: [0]UInt8 = ()
    calls ::= source.calls
    match copy_stream_limited(
        .reader = $&source, .writer = $&sink, .buffer = view(.self = $&empty), .limit = 1
    ) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_stream_buffer { abort } }
    }
    if source.calls != calls { abort }
    status_code = 0
}
