check_fallible_result := (
    .error_tracer : $&Virtual#(ErrorTracer)
) -> !Void = {
    assume error_tracer
}

main := (.system: System) -> (
    .status_code : Int32 = 1
) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    check_fallible_result()!!!
    status_code = 0
}
