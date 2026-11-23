DiscardingExecutor := (.ffi: $&ForeignFunctionInterface, .start: Bool)
implement Executor#(DiscardingExecutor) (
    .state = region(self)
    .submit = (.self: $&DiscardingExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        pending ::= ~request
        if self&.start {
            submitted ::= execute_inline(.request = ~pending, .ffi = self&.ffi)
            match submitted {
                ..ok ~receipt {}
                ..error _ { abort }
            }
        }
        result = ..error(.reason = ..task_start_failed)
    }
)

write := (.value: $&Int32) -> (.result: Int32) {
    value& = 42
    result = 7
}

check := (.ffi: $&ForeignFunctionInterface, .start: Bool) -> () {
    provider ::= DiscardingExecutor(ffi, start)
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 0
    match async#(write)(.args = (.value = $&value)) {
        ..ok ~future { abort }
        ..error failure { match failure.reason {
            ..task_start_failed {}
            ..unsupported_task_value { abort }
            ..executor_mismatch { abort }
        } }
    }
    if start {
        if value != 42 { abort }
    } else {
        if value != 0 { abort }
    }
    value = 1
}

main := (.system: System) -> () {
    check(system.ffi, false)
    check(system.ffi, true)
}
