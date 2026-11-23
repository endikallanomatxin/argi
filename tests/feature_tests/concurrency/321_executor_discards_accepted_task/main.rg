DiscardingExecutor := (.ffi: $&ForeignFunctionInterface)
implement Executor#(DiscardingExecutor) (
    .state = region(self)
    .submit = (.self: $&DiscardingExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        submitted ::= execute_inline(.request = ~request, .ffi = self&.ffi)
        match submitted {
            ..ok ~receipt {}
            ..error _ { abort }
        }
        result = ..error(.reason = ..task_start_failed)
    }
)

write := (.value: $&Int32) -> (.result: Int32) {
    value& = 42
    result = 7
}

main := (.system: System) -> () {
    provider ::= DiscardingExecutor(system.ffi)
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
    if value != 42 { abort }
}
