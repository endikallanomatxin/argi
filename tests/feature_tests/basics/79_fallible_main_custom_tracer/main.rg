..application_failed
CustomTracer : Type = (.marker: UInt8 = 0)
CustomTracer implements ErrorTracer
custom_tracer_storage :: CustomTracer = (.marker = 0)
custom_tracer_virtual :: Virtual#(.abstract: ErrorTracer) = to_virtual#(.abstract: ErrorTracer)(.value = $&custom_tracer_storage)
add_context(.self: $&CustomTracer, .location: SourceLocationId, .context: StringView) -> () := {}
reset_context(.self: $&CustomTracer) -> () := {}
report(.self: $&CustomTracer, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    assume error_tracer ::= $&noop_error_tracer
    write_trace_text(.writer = writer, .text = "custom trace\n")!
    result = ..ok Void()
}
main() -> !Void = ..ok Void() := {
    assume error_tracer ::= $&custom_tracer_virtual
    result = ..error(.reason = ..application_failed)
}
