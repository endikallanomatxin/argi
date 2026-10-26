..default_failed

default_failure := () -> !Void = ..error(
    .reason = ..default_failed
    .tracer = $&noop_error_tracer
) {}

value := () -> !Int32 = ..ok 42 {}

noop := <.t: Type> () -> !Void = ..ok Void() {}

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    if value()!!! != 42 { abort }
    noop<.t: Int32>()!!!
    failure := default_failure()
    match failure {
        ..ok _ { abort }
        ..error error { if error.reason != ..default_failed { abort } }
    }
    status_code = 0
}
