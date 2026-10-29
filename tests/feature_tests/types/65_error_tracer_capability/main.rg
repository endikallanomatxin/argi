..tracer_test_failure

CountingTracer := (.count: UIntNative = 0)

fail := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Int32, .reasons: (..tracer_test_failure))) {
    assume error_tracer

    result = ..error(.reason = ..tracer_test_failure)
}

propagate := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: Int32, .reasons: (..tracer_test_failure))) {
    assume error_tracer

    value := fail()!! "custom context"
    result = ..ok value
}

ok := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Int32 {
    assume error_tracer
    result = ..ok 7
}

context_text := (.counter: $&UIntNative) -> (.view: StringView) {
    counter&= counter&+ 1
    view = "lazy context"
}

success := (
    .counter      : $&UIntNative,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> !Int32 {
    assume error_tracer

    value := ok()!! context_text(.counter = counter)
    result = ..ok value
}

forward := #(.t: Type) (
    .value        : Errable#(.t: t, .reasons: (..tracer_test_failure)),
    .error_tracer : $&Virtual#(.contract: ErrorTracer)                  = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(.t: t, .reasons: (..tracer_test_failure))) {
    assume error_tracer

    unwrapped := value!! "original tracer"
    result = ..ok unwrapped
}

main := () -> (.status_code: Int32) {
    tracer ::= CountingTracer()
    virtual_tracer ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= propagate()
    if tracer.count != 2 {
        status_code = 1
        return
    }
    counter :: UIntNative = 0
    successful ::= success(.counter = $&counter)
    if counter != 0 {
        status_code = 2
        return
    }
    if tracer.count != 2 {
        status_code = 3
        return
    }
    add_context_text(.context = "explicit context")
    if tracer.count != 3 {
        status_code = 4
        return
    }
    other ::= CountingTracer()
    other_virtual ::= to_virtual#(.contract: ErrorTracer)(.value = $&other)
    assume error_tracer ::= $&other_virtual
    forwarded ::= forward#(.t: Int32)(.value = ~failed)
    if tracer.count != 4 {
        status_code = 5
        return
    }
    if other.count != 0 {
        status_code = 6
        return
    }
    ErrorTracer#().reset_context(.self = $&virtual_tracer)
    if tracer.count != 0 {
        status_code = 7
        return
    }
    forwarded_again ::= forward#(.t: Int32)(.value = ~forwarded)
    if tracer.count != 1 {
        status_code = 8
        return
    }
    match forwarded_again {
        ..ok _ { status_code = 9 }
        ..error&err {
            if err&.reason == ..tracer_test_failure {
                status_code = 0
            } else {
                status_code = 10
            }
        }
    }
}

implement ErrorTracer#(CountingTracer) (
    .add_context = (
        .self: $&CountingTracer, .location: SourceLocationId, .context: StringView
    ) -> () {
        self&.count = self&.count + 1
    }

    .reset_context = (.self: $&CountingTracer) -> () { self&.count = 0 }

    .report = (
        .self         : $&CountingTracer,
        .writer       : $&Virtual#(.contract: Writer),
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))) {
        assume error_tracer

        result = ..ok Void()
    }
)
