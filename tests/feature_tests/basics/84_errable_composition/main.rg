other := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Void, .reasons: (..empty))
) {
    assume error_tracer

    result = ..error(.reason = ..empty)
}

bounded := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Void, .reasons: (..composition_failure)) = ..ok Void()
) {
    assume error_tracer

    other()
}

..composition_failure

Box := (.number: Int32)

boxed := #(.t: Type) (.value: t, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: t, .reasons: (..composition_failure))
) {
    assume error_tracer

    result = ..ok ~value
}

pass := #(.t: Type) (.value: t, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: t, .reasons: (..composition_failure))
) {
    assume error_tracer

    payload ::= ~boxed(.value = ~value)!
    result = ..ok ~payload
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    bounded()!!!
    value ::= pass(.value = Box(.number = 42))!!!
    if value.number != 42 { abort }
    match boxed(.value = 7) {
        ..ok number { if number != 7 { abort } } ..error&failure {
            if [failure&.reason != ..composition_failure] { abort }
        }
    }
    status_code = 0
}
