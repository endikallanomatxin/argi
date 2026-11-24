Verify#(.R: Type): Contract = (
    .verify: (.receiver: R, .value: Int32) -> () where {
        reads(receiver)
        isolated()
    }
)

Expected := (.value: Int32)
implement Verify#(&Expected) (
    .verify = (.receiver: &Expected, .value: Int32) -> () {
        if receiver&.value != value { abort }
    }
)

Owner := (.value: Int32)
implement Transferable#(Owner) ()
implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        expected ::= Expected(42)
        verifier ::= Virtual#(Verify)(&expected)
        verifier.verify(.value = self&.value)
    }
)

produce := () -> (.result: Owner) { result = Owner(42) }
pass := (.owner: Owner) -> (.result: Owner) { result = ~owner }

consume := (.owner: Owner) -> (.value: Int32) {
    held ::= ~owner
    value = held.value
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    task ::= unwrap_or_abort(async_owned#(produce)(.args = (), .executor = executor, .ffi = system.ffi))
    owner ::= unwrap_or_abort(await($&task))
    returned ::= unwrap_or_abort(async_owned#(pass)(.args = (.owner = ~owner), .executor = executor, .ffi = system.ffi))
    result ::= unwrap_or_abort(await($&returned))
    consumed ::= unwrap_or_abort(async_owned#(consume)(.args = (.owner = ~result), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&consumed)) != 42 { abort }
}
