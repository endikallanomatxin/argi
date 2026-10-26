Counter := (.value: Int32 = 0)

Counting<.State: Type>: Contract = (
    .bump : (.self: $&State = reach counter, .amount: Int32) -> () where {}
)

implement Counting<Counter> (
    .bump = (.self: $&Counter, .amount: Int32) -> () { self&.value = self&.value + amount }
)

forward := <.T: Type> (.value: T, .counter: $&Counter = reach counter) -> () {
    bump(.amount = value)
}

main := () -> (.status_code: Int32 = 0) {
    state ::= Counter()
    assume counter ::= $&state
    bump(.amount = 7)
    Counting<Counter>.bump(.amount = 3)
    forward(2 | convert<.to: Int32>(_))
    if state.value != 12 { abort }
}
