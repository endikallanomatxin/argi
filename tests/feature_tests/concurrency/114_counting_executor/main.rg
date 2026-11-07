CountingExecutor := (.base: ThreadedExecutor, .submissions: Int32)
implement Executor#(CountingExecutor) (
    .state = region(self.base, self.submissions)
    .submit = (.self: $&CountingExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        pending ::= ~request
        self&.submissions = self&.submissions + 1
        result = Executor#(ThreadedExecutor).submit(.self = $&self&.base, .request = ~pending)
    }
)
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := (.system: System) -> () {
    provider: CountingExecutor = (.base = ThreadedExecutor(.ffi = system.ffi), .submissions = 0)
    assume executor ::= to_virtual#(Executor)($&provider)
    value :: Int32 = 42
    first ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    second ::= unwrap_or_abort(.value = async#(read)(.args = (.value = &value)))
    if provider.submissions != 2 { abort }
    if unwrap_or_abort(.value = await($&first)) != 42 { abort }
    if unwrap_or_abort(.value = await($&second)) != 42 { abort }
}
