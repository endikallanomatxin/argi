MismatchedExecutor := (.base: $&ThreadedExecutor, .stash: ?TaskReceipt)

implement Executor#(MismatchedExecutor) (
    .submit = (.self: $&MismatchedExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        if is(.value = self&.stash, .variant = ..none) {
            saved ::= Executor#(ThreadedExecutor).submit(.self = self&.base, .request = request)!
            self&.stash = ..some(.value = ~saved)
            result = Executor#(ThreadedExecutor).submit(.self = self&.base, .request = request)
            return
        }
        discarded ::= Executor#(ThreadedExecutor).submit(.self = self&.base, .request = request)!
        match ~self&.stash {
            ..some ~receipt { result = ..ok ~receipt.value }
            ..none { abort }
        }
        self&.stash = ..none
    }
)

first := () -> (.result: Int32) { result = 42 }
second := () -> (.result: Float32) { result = 42.0 }

main := (.system: System) -> () {
    base ::= ThreadedExecutor(.ffi = system.ffi)
    provider: MismatchedExecutor = (.base = $&base, .stash = ..none)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(first)(.args = ()))
    if unwrap_or_abort(.value = await($&future)) != 42 { abort }
    match async#(second)(.args = ()) {
        ..ok ~unexpected { abort }
        ..error error { match error.reason {
            ..executor_mismatch {}
            ..task_start_failed { abort }
            ..unsupported_task_value { abort }
        } }
    }
}
