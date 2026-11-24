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

Owner := (.value: Int32)
implement Transferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        -- Observe cleanup of the occupied result after submission reports failure.
        if self&.value == 42 { abort }
    }
)

produce := () -> (.owner: Owner) {
    owner = Owner(42)
}

main := (.system: System) -> () {
    provider ::= DiscardingExecutor(.ffi = system.ffi, .start = true)
    executor ::= Virtual#(Executor)($&provider)
    _ = async_owned#(produce)(.args = (), .executor = executor, .ffi = system.ffi)
}
