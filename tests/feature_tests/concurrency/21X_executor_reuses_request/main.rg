TwiceExecutor := (.base: $&ThreadedExecutor)
implement Executor#(TwiceExecutor) (
    .submit = (.self: $&TwiceExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        first ::= Executor#(ThreadedExecutor).submit(.self = self&.base, .request = ~request)!
        result = Executor#(ThreadedExecutor).submit(.self = self&.base, .request = ~request)
    }
)
work := () -> () {}
main := (.system: System) -> () {
    base ::= ThreadedExecutor(.ffi = system.ffi)
    provider: TwiceExecutor = (.base = $&base)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
    _ = unwrap_or_abort(.value = await($&future))
}
