..application_failed

CustomTracer: Type = (.marker: UInt8 = 0)

custom_tracer_storage :: CustomTracer = (.marker = 0)
custom_tracer_virtual :: Virtual#(.contract: ErrorTracer) = to_virtual#(.contract: ErrorTracer)(
    .value = $&custom_tracer_storage
)

run_main() -> !Void = ..ok Void() := {
    assume error_tracer ::= $&custom_tracer_virtual
    result = ..error(.reason = ..application_failed)
}

main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}

implement ErrorTracer#(CustomTracer)(
    .add_context = (.self: $&CustomTracer, .location: SourceLocationId, .context: StringView) -> () {}

    .reset_context = (.self: $&CustomTracer) -> () {}

    .report = (
            .self   : $&CustomTracer,
            .writer : $&Virtual#(.contract: Writer)
        ) -> (
            .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
        ) {
        assume error_tracer ::= $&noop_error_tracer
        write_trace_text(.writer = writer, .text = "custom trace\n")!
        result = ..ok Void()
    }
)
