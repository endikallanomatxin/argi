step := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Void, .reasons: (..test_error))
) {
    assume error_tracer
    result = ..ok Void()
}

value := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error))
) {
    assume error_tracer
    result = ..ok 5
}

flag := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Bool, .reasons: (..test_error))
) {
    assume error_tracer
    result = ..ok true
}

increment := (.x: Int32) -> (.value: Int32) { value = x + 1 }

statement := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error))
) {
    assume error_tracer

    step()!
    result = ..ok 7
}

argument := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error))
) {
    assume error_tracer

    out ::= increment(.x = value()!)
    result = ..ok out
}

condition := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error))
) {
    assume error_tracer

    if flag()! { result = ..ok 1 } else { result = ..ok 2 }
}

assignment := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Int32, .reasons: (..test_error))
) {
    assume error_tracer

    x :: Int32 = 0
    x = value()!
    result = ..ok x
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    match statement() { ..ok payload { if payload != 7 { abort } } ..error _ { abort } }
    match argument() { ..ok payload { if payload != 6 { abort } } ..error _ { abort } }
    match condition() { ..ok payload { if payload != 1 { abort } } ..error _ { abort } }
    match assignment() { ..ok payload { if payload != 5 { abort } } ..error _ { abort } }
}
