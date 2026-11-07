BadExecutor := (.base: $&ThreadedExecutor)
implement Executor#(BadExecutor) (
    .state = region(self.base)
    .submit = (.self: $&BadExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        request._output_size = 1
        result = Executor#(ThreadedExecutor).submit(.self = self&.base, .request = ~request)
    }
)
compute := () -> (.result: Int32) { result = 42 }
main := (.system: System) -> () {
    base ::= ThreadedExecutor(.ffi = system.ffi)
    provider: BadExecutor = (.base = $&base)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(compute)(.args = ()))
}
