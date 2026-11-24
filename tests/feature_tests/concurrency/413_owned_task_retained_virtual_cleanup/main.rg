Verify#(.R: Type): Contract = (
    .verify: (.receiver: R, .value: Int32) -> () where { writes(receiver) isolated() }
)
Expected := (.value: Int32)
implement ConcurrentAlias#(Expected) ()
implement Verify#($$&Expected) (
    .verify = (.receiver: $$&Expected, .value: Int32) -> () {
        view ::= trusted_concurrent_view(.shared = receiver)
        if view&.value != value { abort }
    }
)
Owner := (.verifier: Virtual#(Verify), .value: Int32)
implement StructurallyTransferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        self&.verifier.verify(.value = self&.value)
    }
)
consume := (.owner: Owner) -> (.value: Int32) {
    held ::= ~owner
    value = held.value
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    expected ::= Expected(42)
    shared ::= $$&expected
    owner ::= Owner(.verifier = Virtual#(Verify)(shared), .value = 42)
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.owner = ~owner), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 42 { abort }
    recover_ordinary(.owner = $&expected)
}
