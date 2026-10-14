ProbeTracer: Type = (.count: UIntNative = 0)

checked_to_int8#(.t: Type)(.value: t) -> (.result: Errable#(.t: Int8, .reasons: (..out_of_range))) := {
    result = ..ok value | convert#(.to: Int8)(_)!
}

main() -> (.status_code: Int32 = 0) := {
    tracer ::= ProbeTracer()
    virtual_tracer ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    valid: Int64 = 127
    if unwrap_or_abort(.value = checked_to_int8(.value = valid)) != 127 or tracer.count != 0 {
        status_code = 1
        return
    }
    invalid: Int64 = 128
    failed ::= checked_to_int8(.value = invalid)
    if is(.value = failed, .variant = ..error) == false or tracer.count != 2 {
        status_code = 2
        return
    }
}

implement ErrorTracer#(ProbeTracer)(
    .add_context = (.self: $&ProbeTracer, .location: SourceLocationId, .context: StringView) -> () {
        self&.count = self&.count + 1
    }

    .reset_context = (.self: $&ProbeTracer) -> () { self&.count = 0 }

    .report = (
            .self   : $&ProbeTracer,
            .writer : $&Virtual#(.contract: Writer)
        ) -> (
            .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
        ) {
        result = ..ok Void()
    }
)
