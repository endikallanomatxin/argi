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

produce := () -> (.owner: Owner) {
    owner = Owner(42)
}

run := (.ffi: $&ForeignFunctionInterface, .start: Bool) -> () {
    provider ::= DiscardingExecutor(.ffi = ffi, .start = start)
    executor ::= Virtual#(Executor)($&provider)
    match async_owned#(produce)(.args = (), .executor = executor, .ffi = ffi) {
        ..ok ~unexpected { abort }
        ..error _ {}
    }
}

main := (.system: System) -> () {
    run(.ffi = system.ffi, .start = false)
    if drops != 0 { abort }
    run(.ffi = system.ffi, .start = true)
    if drops != 1 { abort }
}
