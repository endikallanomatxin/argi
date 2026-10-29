DummyWriter := (
    .flush_count : Int32 = 0
)

Wrapper := (
    .base : $&DummyWriter
)

accept := #(.WriterType: Type: Writer#(WriterType)) (.writer: $&WriterType) -> (
    .status_code : Int32
) {
    Writer#().flush(.self = writer)
    status_code = 0
}

main := () -> (.status_code: Int32) {
    base :: DummyWriter = (
        .flush_count = 0
    )
    wrapper :: Wrapper = (
        .base = $&base
    )

    _ ::= accept(.writer = $&wrapper)
    status_code = 0
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

        self&
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

        self&.flush_count = self&.flush_count + 1
        result = ..ok(.value = Void())
    }
)

implement Writer#(Wrapper) (
    .write_byte = (
        .self         : $&Wrapper,
        .byte         : UInt8,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        Writer#().write_byte(.self = self&.base, .byte = byte)
        result = ..ok(.value = Void())
    }

    .flush = (
        .self         : $&Wrapper,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        Writer#().flush(.self = self&.base)
        result = ..ok(.value = Void())
    }
)
