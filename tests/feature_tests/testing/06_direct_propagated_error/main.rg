..file_not_found

some_fallible_call := (.error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(.t: Void, .reasons: (..file_not_found))
) {
    assume error_tracer

    result = ..error(.reason = ..file_not_found)
}

test direct_propagation := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !() {
    assume error_tracer

    some_fallible_call()!
}
