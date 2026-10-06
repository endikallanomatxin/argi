..default_failed
default_failure() -> !Void = ..error(.reason = ..default_failed, .trace = (.tracer = $&noop_error_tracer)) := {}
value() -> !Int32 = ..ok 42 := {}
noop#(.t: Type)() -> !Void = ..ok Void() := {}
run_main() -> !Void = ..ok Void() := {
    if value()! != 42 { abort }
    noop#(.t: Int32)()!
    failure := default_failure()
    match failure {
        ..ok _ { abort }
        ..error error { if error.reason != ..default_failed { abort } }
    }
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
