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

drops :: UIntNative = 0

Owner := (.value: Int32)
implement Transferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        -- Observe cleanup of the occupied result after submission reports failure.
        if self&.value != 42 { abort }
        drops = drops + 1
    }
)

forward := (.input: Owner) -> (.owner: Owner) {
    owner = ~input
}

forward_through_helper := (.input: Owner) -> (.owner: Owner) {
    owner = forward(.input = ~input)
}

run := (.ffi: $&ForeignFunctionInterface, .start: Bool) -> () {
    provider ::= DiscardingExecutor(.ffi = ffi, .start = start)
    executor ::= Virtual#(Executor)($&provider)
    input ::= Owner(42)
    match async_owned#(forward_through_helper)(.args = (.input = ~input), .executor = executor, .ffi = ffi) {
        ..ok ~unexpected { abort }
        ..error failure {
            if is(.value = failure.reason, .variant = ..task_start_failed) == false { abort }
        }
    }
}

main := (.system: System) -> () {
    run(.ffi = system.ffi, .start = false)
    if drops != 1 { abort }
    run(.ffi = system.ffi, .start = true)
    if drops != 2 { abort }
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    {
        input ::= Owner(42)
        task ::= unwrap_or_abort(async_owned#(forward_through_helper)(.args = (.input = ~input), .executor = executor, .ffi = system.ffi))
        owner ::= unwrap_or_abort(await($&task))
        if owner.value != 42 or drops != 2 { abort }
    }
    if drops != 3 { abort }
    {
        input ::= Owner(42)
        task ::= unwrap_or_abort(async_owned#(forward_through_helper)(.args = (.input = ~input), .executor = executor, .ffi = system.ffi))
        if drops != 3 { abort }
    }
    if drops != 4 { abort }
}
