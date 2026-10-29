FirstWriter: Type = ()

FirstWriterInitArgs: Type = ()

implement Init#(FirstWriter, FirstWriterInitArgs) (
    .Result : Type = FirstWriter

    .init = FirstWriterInitArgs -> (.result: Result) {
        result = ()
    }
)

SecondWriter := (.marker: Int32 = 0)

SecondWriterInitArgs2: Type = ()

implement Init#(SecondWriter, SecondWriterInitArgs2) (
    .Result : Type = SecondWriter

    .init = SecondWriterInitArgs2 -> (.result: Result) {
        result = ()
    }
)

Holder := #(.WriterType: Type: Writer#(WriterType)) (
    .writer : $&WriterType
)

set_first := (.p: $&Holder#(FirstWriter), .writer: $&FirstWriter) -> () {
    p&.writer = writer
}

set_second := (.p: $&Holder#(FirstWriter), .writer: $&SecondWriter) -> () {
    p&.writer = writer
}

main := () -> (.status_code: Int32) {
    first :: FirstWriter = FirstWriter()
    second :: SecondWriter = SecondWriter()
    holder :: Holder#(FirstWriter)

    set_first(.p = $&holder, .writer = $&first)
    set_second(.p = $&holder, .writer = $&second)

    status_code = 0
}

implement Writer#(FirstWriter) (
    .write_byte = (
        .self         : $&FirstWriter,
        .byte         : UInt8,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        _ ::= byte
        result = ..ok(.value = Void())
    }

    .flush = (
        .self         : $&FirstWriter,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        result = ..ok(.value = Void())
    }
)

implement Writer#(SecondWriter) (
    .write_byte = (
        .self         : $&SecondWriter,
        .byte         : UInt8,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        _ ::= byte
        result = ..ok(.value = Void())
    }

    .flush = (
        .self         : $&SecondWriter,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        result = ..ok(.value = Void())
    }
)
