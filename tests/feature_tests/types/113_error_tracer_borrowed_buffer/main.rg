Storage := (.aligner: UIntNative, .bytes: [291]UInt8)

ProbeWriter := (.bytes: UIntNative = 0)

main := () -> (.status_code: Int32 = 0) {
    -- The numeric prefix aligns bytes; slicing at one deliberately misaligns
    -- slot headers. Sentinels also cover the unused tail and both boundaries.
    storage ::= Storage(.aligner = 0, .bytes = zeroed#(.t: [291]UInt8)())
    storage.bytes[0] = 77
    storage.bytes[289] = 88
    storage.bytes[290] = 99
    backing ::= view($&storage.bytes)
    buffer ::= unwrap_or_abort(.value = slice(.self = &backing, .start = 1, .count = 289))
    tracer ::= FixedSizeErrorTracer(.buffer = buffer)
    context: StringView = "unaligned context"
    location ::= error_location_id()
    ErrorTracer#().add_context(.self = $&tracer, .location = location, .context = context)
    ErrorTracer#().add_context(.self = $&tracer, .location = location, .context = context)
    ErrorTracer#().add_context(.self = $&tracer, .location = location, .context = context)
    writer ::= ProbeWriter()
    virtual_writer ::= to_virtual#(Writer)($&writer)
    unwrap_or_abort(
        .value = ErrorTracer#().report(.self = $&tracer, .writer = $&virtual_writer)
    )
    if writer.bytes <= 43 or writer.bytes > 4096 {
        status_code = 1
        return
    }
    if storage.bytes[0] != 77 or storage.bytes[289] != 88 or storage.bytes[290] != 99 {
        status_code = 2
        return
    }
    ErrorTracer#().reset_context(.self = $&tracer)
    writer.bytes = 0
    unwrap_or_abort(
        .value = ErrorTracer#().report(.self = $&tracer, .writer = $&virtual_writer)
    )
    if writer.bytes != 43 {
        status_code = 3
        return
    }
    deinit(.self = $&tracer)
    storage.bytes[1] = 0

    empty ::= FixedSizeErrorTracer(.buffer = view($&zeroed#(.t: [0]UInt8)()))
    tiny ::= FixedSizeErrorTracer(.buffer = view($&zeroed#(.t: [143]UInt8)()))
    ErrorTracer#().add_context(.self = $&empty, .location = location, .context = context)
    ErrorTracer#().add_context(.self = $&tiny, .location = location, .context = context)
    writer.bytes = 0
    unwrap_or_abort(.value = ErrorTracer#().report(.self = $&empty, .writer = $&virtual_writer))
    empty_count ::= writer.bytes
    writer.bytes = 0
    unwrap_or_abort(.value = ErrorTracer#().report(.self = $&tiny, .writer = $&virtual_writer))
    if empty_count <= 43 or writer.bytes != empty_count {
        status_code = 4
        return
    }
    ErrorTracer#().reset_context(.self = $&empty)
    ErrorTracer#().reset_context(.self = $&tiny)
    writer.bytes = 0
    unwrap_or_abort(.value = ErrorTracer#().report(.self = $&tiny, .writer = $&virtual_writer))
    if writer.bytes != 43 { status_code = 5 }
}

implement Writer#(ProbeWriter) (
    .write_byte = (
        .self         : $&ProbeWriter,
        .byte         : UInt8,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        self&.bytes = self&.bytes + 1
        result = ..ok Void()
    }

    .flush = (
        .self         : $&ProbeWriter,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer
        result = ..ok Void()
    }
)
