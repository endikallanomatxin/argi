..partial_construction_failed

Counter: Type = (.count: Int32)

Child: Type = (.counter: $&Counter)

Parent: Type = (.child: Child, .missing: Int32)

implement Deinit#(Child) (
    .deinit = (.self: $&Child) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

implement Deinit#(Parent) (
    .deinit = (.self: $&Parent) -> () { abort }
)

fail := (.tracer: $&Virtual#(.contract: ErrorTracer)) -> (
    .result : Errable#(Int32, (..partial_construction_failed))
) {
    result = ..error(.reason = ..partial_construction_failed, .tracer = tracer)
}

build_partial := (.counter: $&Counter, .tracer: $&Virtual#(.contract: ErrorTracer)) -> (
    .result : Errable#(Int32, (..partial_construction_failed))
) {
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
    build_partial(.counter = $&counter, .tracer = $&erased) handle error {
        match error.reason { ..partial_construction_failed {} }
    }
    if counter.count != 1 { abort }
    result = 42
}

main := () -> (.status_code: Int32) {
    if #run probe() != 42 { abort }
    #if probe() == 42 {
        status_code = probe()
    } else {
        abort
    }
}
