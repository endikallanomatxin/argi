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
implement Verify#($&Expected) (
    .verify = (.receiver: $&Expected, .value: Int32) -> () {
        if receiver&.value != value { abort }
    }
)
Owner := (.verifier: Virtual#(Verify), .value: Int32)
implement StructurallyTransferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        self&.verifier.verify(.value = self&.value)
    }
)
replace_verifier := (.owner: $&Owner, .verifier: Virtual#(Verify)) -> () {
    owner&.verifier = verifier
}
consume := (.owner: Owner) -> (.value: Int32) {
    held ::= ~owner
    value = held.value
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    expected ::= Expected(42)
    other ::= Expected(42)
    shared ::= $$&expected
    other_local ::= $&other
    owner ::= Owner(.verifier = Virtual#(Verify)(other_local), .value = 42)
    replace_verifier(.owner = $&owner, .verifier = Virtual#(Verify)(shared))
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.owner = ~owner), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 42 { abort }
    recover_ordinary(.owner = $&expected)
}
