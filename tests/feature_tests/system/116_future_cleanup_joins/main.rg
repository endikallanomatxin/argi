work := () -> (.result: UIntNative) {
    value :: UIntNative = 0
    while value < 1000000 { value = value + 1 }
    result = value
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    {
        future ::= unwrap_or_abort(.value = async#(work)(.args = ()))
        moved ::= ~future
    }
    -- Cleanup joins before reclaiming the moved task's native buffers.
}
