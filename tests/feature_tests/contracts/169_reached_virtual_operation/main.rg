Counter: Type = (.value: Int32 = 0)

Counting#(.State: Type): Contract = (
    .bump : (.self: $&State = reach counter, .amount: Int32) -> () where {}
)

implement Counting#(Counter)(
    .bump = (.self: $&Counter, .amount: Int32) -> () { self&.value = self&.value + amount }
)

main := () -> (.status_code: Int32 = 0) {
    state ::= Counter()
    erased ::= to_virtual#(.contract: Counting)(.value = $&state)
    assume counter ::= $&erased
    bump(.amount = 42)
    if state.value != 42 { abort }
}
