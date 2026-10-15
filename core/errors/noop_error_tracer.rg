-- The virtual wrapper and its receiver both have program lifetime.
NoopErrorTracer: Type = (.marker: UInt8 = 0)

noop_error_tracer_storage :: NoopErrorTracer = (.marker = 0)
noop_error_tracer :: Virtual#(.contract: ErrorTracer) = to_virtual#(.contract: ErrorTracer)(
    .value = $&noop_error_tracer_storage
)

implement ErrorTracer#(NoopErrorTracer) (
    .add_context = (
        .self: $&NoopErrorTracer, .location: SourceLocationId, .context: StringView
    ) -> () {}

    .reset_context = (.self: $&NoopErrorTracer) -> () {}

    .report = (.self: $&NoopErrorTracer, .writer: $&Virtual#(.contract: Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        result = ..ok Void()
    }
)
