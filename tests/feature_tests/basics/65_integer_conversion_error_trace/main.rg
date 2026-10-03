ProbeTracer : Type = (.count: UIntNative = 0)
ProbeTracer implements ErrorTracer
add_context(.self: $&ProbeTracer, .location: SourceLocationId, .context: StringView) -> () := {
    self&.count = self&.count + 1
}
reset_context(.self: $&ProbeTracer) -> () := { self&.count = 0 }
report(.self: $&ProbeTracer, .writer: $&Virtual#(.abstract: Writer)) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) := {
    result = ..ok Void()
}
convert#(.t: Type)(.value: t) -> (.result: Errable#(.t: Int8, .reasons: (..out_of_range))) := {
    result = ..ok Int8(.value = value)!
}
main() -> (.status_code: Int32 = 0) := {
    tracer ::= ProbeTracer()
    virtual_tracer ::= to_virtual#(.abstract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    valid : Int64 = 127
    if unwrap_or_abort(.value = convert(.value = valid)) != 127 or tracer.count != 0 { status_code = 1 return }
    invalid : Int64 = 128
    failed ::= convert(.value = invalid)
    if is(.value = failed, .variant = ..error) == false or tracer.count != 2 { status_code = 2 return }
}
