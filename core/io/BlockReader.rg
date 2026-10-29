BlockReader#(.Stream: Type): Contract = (
    .read_block : (
        .self         : $&Stream,
        .buffer       : MutableArrayView#(.t: UInt8),
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(UIntNative, (..stream_read_failed))) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
)
