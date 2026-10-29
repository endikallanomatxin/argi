BlockReader#(.Stream: Type): Contract = (
    .read_block : (
        .self         : $&Stream,
        .buffer       : MutableArrayView#(.t: UInt8),
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(UIntNative, (..stream_read_failed))) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
)
