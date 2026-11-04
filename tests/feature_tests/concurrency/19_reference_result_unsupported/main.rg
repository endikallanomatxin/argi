identity := (.value: &Int32) -> (.result: &Int32) { result = value }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 42
    match async#(identity)(.args = (.value = &value)) {
        ..ok ~unexpected { abort }
        ..error error { match error.reason {
            ..unsupported_task_value {}
            ..task_start_failed { abort }
            ..executor_mismatch { abort }
        } }
    }
    value = 7
    if value != 7 { abort }
}
