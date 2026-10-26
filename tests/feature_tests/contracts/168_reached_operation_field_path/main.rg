Counter := (.value: Int32 = 0)

Capabilities := (.counter: $&Counter)

Counting<.State: Type>: Contract = (
    .bump : (.self: $&State = reach capabilities.counter, .amount: Int32) -> () where {}
)

implement Counting<Counter> (
    .bump = (.self: $&Counter, .amount: Int32) -> () { self&.value = self&.value + amount }
)

main := () -> (.status_code: Int32 = 0) {
    state ::= Counter()
    assume capabilities ::= Capabilities(.counter = $&state)
    bump(.amount = 42)
    if state.value != 42 { abort }
}
