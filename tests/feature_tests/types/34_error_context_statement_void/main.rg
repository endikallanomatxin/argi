fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Void, .reasons: (..test_error))
) {
    assume error_tracer

    result = ..error(.reason = ..test_error)
}

run := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error))
) {
    assume error_tracer

    fail()!! "while stepping"
    result = ..ok 0
}

main := () -> (.status_code: Int32) {
    tracer ::= ProbeTracer()
    virtual_tracer ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= run()
    if tracer.count != 2 {
        status_code = 1
        return
    }
    if tracer.line != 14 {
        status_code = 2
        return
    }
    if tracer.column != 11 {
        status_code = 3
        return
    }
    if tracer.context_matches == false {
        status_code = 4
        return
    }
    match failed {
        ..ok _ { status_code = 5 }
        ..error _ { status_code = 0 }
    }
}

ProbeTracer := (
    .count           : UIntNative = 0
    .line            : UIntNative = 0
    .column          : UIntNative = 0
    .context_matches : Bool       = false
)

implement ErrorTracer#(ProbeTracer) (
    .add_context = (.self: $&ProbeTracer, .location: SourceLocationId, .context: StringView) -> (
    ) {
        reader ::= source_location(.id = location).location
        self&.count = self&.count + 1
        self&.line = reader.line
        self&.column = reader.column
        self&.context_matches = equals(.left = context, .right = "while stepping").ok
    }

    .reset_context = (.self: $&ProbeTracer) -> () { self&.count = 0 }

    .report = (
        .self         : $&ProbeTracer,
        .writer       : $&Virtual#(Writer),
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer
        result = ..ok Void()
    }
)
