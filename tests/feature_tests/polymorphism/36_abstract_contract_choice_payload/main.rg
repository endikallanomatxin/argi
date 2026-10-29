DummyWriter := (
    .count : Int32 = 0
)

relay := #(.WriterType: Type: Writer#(WriterType)) (
    .writer       : $&WriterType,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
    assume error_tracer

    Writer#().write_byte(.self = writer, .byte = 65)
    result = ..ok(.value = Void())
}

main := () -> (.status_code: Int32) {
    writer ::= DummyWriter()
    relay(.writer = $&writer)
    status_code = 0
    if writer.count != 1 {
        status_code = 1
    }
}

implement Writer#(DummyWriter) (
    .write_byte = (
        .self         : $&DummyWriter,
        .byte         : UInt8,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        self&.count = self&.count + 1
        byte
        result = ..ok(.value = Void())
    }

    .flush = (
        .self         : $&DummyWriter,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        self
        result = ..ok(.value = Void())
    }
)
