ForwardingExecutor := (.base: $&ThreadedExecutor)
implement Executor#(ForwardingExecutor) (
    .submit = (.self: $&ForwardingExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        result = Executor#(ThreadedExecutor).submit(.self = self&.base, .request = ~request)
    }
)
compute := (.value: Int32 = 21) -> (.result: Int32) { result = value * 2 }
main := (.system: System) -> () {
    base ::= ThreadedExecutor(.ffi = system.ffi)
    provider: ForwardingExecutor = (.base = $&base)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(compute)(.args = ()))
    value ::= unwrap_or_abort(.value = await($&future))
    if value != 42 { abort }
}
