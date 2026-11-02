CountingTracer := (.count: Int32, .location: UInt32)

implement ErrorTracer#(CountingTracer) (
    .add_context = (
        .self: $&CountingTracer, .location: SourceLocationId, .context: StringView
    ) -> () {
        if byte_length(&context).count != 0 { abort }
        self&.count = self&.count + 1
        self&.location = location.value
    }
    .reset_context = (.self: $&CountingTracer) -> () {}
    .report        = (.self: $&CountingTracer, .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {

        result = ..ok Void()
    }
)

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    tracer :: CountingTracer = (.count = 0, .location = 0)
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    captured ::= capture_error_tracer(.location = (.value = 17), .error_tracer = $&erased)
    ErrorTracer#().reset_context(captured)
    if tracer.count != 1 { abort }
    if tracer.location != 17 { abort }
    status_code = 42
}
