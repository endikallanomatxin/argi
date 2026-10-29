BlockWriter#(.Stream: Type): Contract = (
    .write_block : (
        .self: $&Stream, .buffer: ArrayView#(.t: UInt8), .error_tracer: $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(UIntNative, (..stream_write_failed, ..stream_flush_failed))) where {
        on result ..ok {}
        on result ..error { depends_on(result, error_tracer) }
    }
)
