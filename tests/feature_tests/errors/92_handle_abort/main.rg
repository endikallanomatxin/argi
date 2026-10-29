..missing

attempt := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Errable#(Void, (..missing))) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    attempt() handle error { abort }
}
