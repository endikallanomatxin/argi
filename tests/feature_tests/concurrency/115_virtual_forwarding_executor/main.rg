ForwardingExecutor := (.base: Virtual#(Executor))
implement Executor#(ForwardingExecutor) (
    .state = region(self.base.state)
    .submit = (.self: $&ForwardingExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        pending ::= ~request
        result = Executor#().submit(.self = $&self&.base, .request = ~pending)
    }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    base ::= ThreadedExecutor(.ffi = system.ffi)
    provider: ForwardingExecutor = (.base = Virtual#(Executor)($&base))
    assume executor ::= Virtual#(Executor)($&provider)
    value :: Int32 = 42
    future ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if unwrap_or_abort(.value = await($&future)) != 42 { abort }
}
