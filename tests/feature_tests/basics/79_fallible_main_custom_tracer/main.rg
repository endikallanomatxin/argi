..application_failed

CustomTracer := (.marker: UInt8 = 0)

custom_tracer_storage :: CustomTracer = (.marker = 0)
custom_tracer_virtual :: Virtual#(ErrorTracer) = to_virtual#(.contract: ErrorTracer)(
    .value = $&custom_tracer_storage
)

check_fallible_result := () -> !!Void = ..ok Void() {
    assume error_tracer ::= $&custom_tracer_virtual
    result = ..error(.reason = ..application_failed)
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    check_fallible_result()!!!
    status_code = 0
}

implement ErrorTracer#(CustomTracer) (
    .add_context = (.self: $&CustomTracer, .location: SourceLocationId, .context: StringView) -> (
    ) {}

    .reset_context = (.self: $&CustomTracer) -> () {}

    .report = (.self: $&CustomTracer, .writer: $&Virtual#(Writer)) -> (
        .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
    ) {

        write_trace_text(.writer = writer, .text = "custom trace\n")!
        result = ..ok Void()
    }
)
