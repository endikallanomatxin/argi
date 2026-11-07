write := (.value: $&Int32) -> () { value& = 42 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
FailingExecutor := (.unused: Bool)
implement Executor#(FailingExecutor) (
    .state = region(self)
    .submit = (.self: $&FailingExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        pending ::= ~request
        result = ..error(.reason = ..task_start_failed)
    }
)
main := () -> () {
    provider: FailingExecutor = (.unused = false)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 1
    match async#(write)(.args = (.value = $&value)) {
        ..ok _ { abort }
        ..error error { match error.reason {
            ..task_start_failed {}
            ..unsupported_task_value { abort }
            ..executor_mismatch { abort }
        } }
    }
    value = 42
    if value != 42 { abort }
}
