Counter := (.count: UIntNative = 0)

implement ErrorTracer#(Counter) (
    .add_context = (.self: $&Counter, .location: SourceLocationId, .context: StringView) -> () {
        self&.count = self&.count + 1
    }
    .reset_context = (.self: $&Counter) -> () { self&.count = 0 }
    .report        = (.self: $&Counter, .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {

        result = ..ok Void()
    }
)

main := () -> (.status_code: Int32 = 0) {
    tracer ::= Counter()
    noop ::= NoopErrorTracer()
    reset_context($&noop)
    ErrorTracer#(
        Counter
    ).add_context($&tracer, .location = error_location_id(), .context = "first")
    if tracer.count != 1 { abort }
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&erased
    add_context_text(.context = "second")
    if tracer.count != 2 { abort }
    ErrorTracer#().reset_context($&erased)
    if tracer.count != 0 { abort }
}
