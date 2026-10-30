..partial_construction_failed

Counter := (.count: Int32)

Child := (.counter: $&Counter)

Parent := (.child: Child, .missing: Int32)

implement Deinit#(Child) (
    .deinit = (.self: $&Child) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

implement Deinit#(Parent) (
    .deinit = (.self: $&Parent) -> () { abort }
)

fail := (.tracer: $&Virtual#(ErrorTracer), .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(
        Int32,
        (..partial_construction_failed),
        .error_type : ErrorWithTrace#((..partial_construction_failed))
    )
) {
    assume error_tracer

    result = ..error(.reason = ..partial_construction_failed, .tracer = tracer)
}

build_partial := (
    .counter      : $&Counter,
    .tracer       : $&Virtual#(ErrorTracer),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (
    .result : Errable#(
        Int32,
        (..partial_construction_failed),
        .error_type : ErrorWithTrace#((..partial_construction_failed))
    )
) {
    assume error_tracer

    parent :: Parent
    parent.child = Child(.counter = counter)
    value ::= fail(tracer)!
    parent.missing = value
    result = ..ok 42
}

probe := () -> (.result: Int32) {
    counter :: Counter = (.count = 0)
    tracer :: NoopErrorTracer = (.marker = 0)
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&erased
    build_partial(.counter = $&counter, .tracer = $&erased) handle error {
        match error.reason { ..partial_construction_failed {} }
    }
    if counter.count != 1 { abort }
    result = 42
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    if #run () -> (.value: Int32) { value = probe() } != 42 { abort }
    #if probe() == 42 {
        status_code = probe()
    } else {
        abort
    }
}
