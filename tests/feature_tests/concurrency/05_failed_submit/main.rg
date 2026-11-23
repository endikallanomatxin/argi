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
drops :: Int32 = 0
Ticket := (.value: Int32)

implement Deinit#(Ticket) (
    .deinit = (.self: $&Ticket) -> () {
        if self&.value != 42 { abort }
        drops = drops + 1
    }
)

consume_ticket := (.ticket: Ticket) -> (.result: Int32) {
    owner ::= ~ticket
    result = owner.value
}

main := () -> () {
    provider: FailingExecutor = (.unused = false)
    assume executor ::= Virtual#(Executor)($&provider)
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
    {
        ticket :: Ticket = (.value = 42)
        match async#(consume_ticket)(.args = (.ticket = ~ticket)) {
            ..ok _ { abort }
            ..error failure { match failure.reason {
                ..unsupported_task_value {}
                ..task_start_failed {}
                ..executor_mismatch { abort }
            } }
        }
        if drops != 1 { abort }
    }
    if drops != 1 { abort }
}
