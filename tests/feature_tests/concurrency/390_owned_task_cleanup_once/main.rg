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

Owner := (.drops: $&Int32)
implement Transferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        self&.drops& = self&.drops& + 1
    }
)
consume := (.owner: Owner) -> (.value: Int32) {
    held ::= ~owner
    value = 42
}
check_failed_submit := (.ffi: $&ForeignFunctionInterface, .accept: Bool) -> () {
    provider ::= DiscardingExecutor(.ffi = ffi, .start = accept)
    executor ::= Virtual#(Executor)($&provider)
    drops :: Int32 = 0
    owner ::= Owner($&drops)
    match async_owned#(consume)(.args = (.owner = ~owner), .executor = executor, .ffi = ffi) {
        ..ok ~task { abort }
        ..error failure {
            if is(.value = failure.reason, .variant = ..task_start_failed) == false { abort }
        }
    }
    if drops != 1 { abort }
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    drops :: Int32 = 0
    owner ::= Owner($&drops)
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.owner = ~owner), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 42 { abort }
    if drops != 1 { abort }
    check_failed_submit(.ffi = system.ffi, .accept = false)
    check_failed_submit(.ffi = system.ffi, .accept = true)
}
