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
make_owner := (
    .first: Virtual#(Verify), .second: Virtual#(Verify), .choose_first: Bool
) -> (.owner: Owner) {
    if choose_first {
        owner = Owner(.verifier = first, .value = 42)
    } else {
        owner = Owner(.verifier = second, .value = 42)
    }
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
    choose_first ::= expected.value == 42
    shared ::= $$&expected
    other_shared ::= $$&other
    owner ::= make_owner(.first = Virtual#(Verify)(shared), .second = Virtual#(Verify)(other_shared), .choose_first = choose_first)
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.owner = ~owner), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 42 { abort }
    recover_ordinary(.owner = $&expected)
    recover_ordinary(.owner = $&other)
}
