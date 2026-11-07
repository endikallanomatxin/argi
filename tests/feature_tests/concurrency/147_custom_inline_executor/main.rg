LocalExecutor := (.ffi: $&ForeignFunctionInterface)
implement Executor#(LocalExecutor) (
    .state = region(self)
    .submit = (.self: $&LocalExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        result = execute_inline(.request = ~request, .ffi = self&.ffi)
    }
)
compute := (.x: Int32) -> (.result: Int32) { result = x * 2 }
main := (.system: System) -> () {
    provider: LocalExecutor = (.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    future ::= unwrap_or_abort(.value = async#(compute)(.args = (.x = 21)))
    if unwrap_or_abort(.value = await($&future)) != 42 { abort }
}
