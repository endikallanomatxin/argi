..missing

attempt := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Errable#(Void, (..missing))) {
    assume error_tracer

    result = ..error(.reason = ..missing)
}

main := (.system: System) -> () {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    attempt()!!!
    abort
}
