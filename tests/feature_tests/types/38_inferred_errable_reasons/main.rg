..test_error

fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error))
) {
    assume error_tracer

    result = ..error(.reason = ..test_error)
}

from_propagation := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Int32 {
    assume error_tracer

    value := fail()!
    result = ..ok value + 1
}

direct_error := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Int32 {
    assume error_tracer

    result = ..error(.reason = ..test_error)
}

explicit_output := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Errable#(.t: Int32)) {
    assume error_tracer

    value := fail()!
    result = ..ok value + 2
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    match from_propagation() {
        ..ok _ { abort }
        ..error&err { match err&.reason { ..test_error {} } }
    }
    match direct_error() {
        ..ok _ { abort }
        ..error&err { match err&.reason { ..test_error {} } }
    }
    match explicit_output() {
        ..ok _ { abort }
        ..error&err { match err&.reason { ..test_error {} } }
    }
}
