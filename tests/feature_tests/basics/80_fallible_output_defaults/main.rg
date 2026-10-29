..default_failed

default_failure := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Void = ..error(
    .reason = ..default_failed
    .tracer = $&noop_error_tracer
) {
    assume error_tracer
}

value := (.error_tracer: $&Virtual#(ErrorTracer)) -> !Int32 = ..ok 42 {
    assume error_tracer
}

noop := #(.t: Type) (.error_tracer: $&Virtual#(ErrorTracer)) -> !Void = ..ok Void() {
    assume error_tracer
}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume error_tracer ::= $&noop_error_tracer
    assume writer ::= $&system.terminal&.stderr
    if value()!!! != 42 { abort }
    noop#(.t: Int32)()!!!
    failure := default_failure()
    match failure {
        ..ok _ { abort }
        ..error error { if error.reason != ..default_failed { abort } }
    }
    status_code = 0
}
