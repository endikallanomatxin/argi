Reader#(.Stream: Type): Contract = (
    .read_byte : (
        .self         : $&Stream,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(ReadByte, (..stream_read_failed))) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
)
