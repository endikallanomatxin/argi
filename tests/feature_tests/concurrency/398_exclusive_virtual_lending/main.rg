Update#(.R: Type): Contract = (
    .increment: (.receiver: R) -> (.value: Int32) where { writes(receiver) isolated() }
)
Counter := (.value: Int32)
implement Update#($&Counter) (
    .increment = (.receiver: $&Counter) -> (.value: Int32) {
        receiver&.value = receiver&.value + 1
        value = receiver&.value
    }
)
worker := (.view: Virtual#(Update)) -> (.value: Int32) {
    value = view.increment().value
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    counter ::= Counter(41)
    view ::= Virtual#(Update)($&counter)
    future ::= unwrap_or_abort(async#(worker)(.args = (.view = view)))
    if unwrap_or_abort(await($&future)) != 42 { abort }
    if counter.value != 42 { abort }
}
