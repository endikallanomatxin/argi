check_fallible_result := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [NoopErrorTracer() | to_virtual#(
            .contract : ErrorTracer
        )($&_) | $&_]
) -> !Void = {
    assume error_tracer
}

main := (.system: System) -> (
    .status_code : Int32 = 1
) {
    assume writer ::= $&system.terminal&.stderr
    check_fallible_result()!!!
    status_code = 0
}
