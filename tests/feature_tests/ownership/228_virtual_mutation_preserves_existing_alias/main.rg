Mutator#(.Participant: Type): Contract = (
    .mutate : (.self: $&Participant) -> () where {}
)

Stateful := (.counter: Int32)

Noop := (.marker: UInt8)

implement Mutator#(Stateful) (.mutate = _impl_mutate_Stateful)

implement Mutator#(Noop) (.mutate = _impl_mutate_Noop)

_impl_mutate_Stateful := (.self: $&Stateful) -> () {
    self&.counter = self&.counter + 1
}

_impl_mutate_Noop := (.self: $&Noop) -> () {}

register_noop := (.value: $&Noop) -> () {
    _ ::= to_virtual#(.contract: Mutator)(.value = value)
}

main := () -> (.status_code: Int32) {
    noop ::= Noop(.marker = 0)
    register_noop(.value = $&noop)
    state ::= Stateful(.counter = 0)
    alias ::= $&state
    virtual ::= to_virtual#(.contract: Mutator)(.value = $&state)
    mutate(.self = $&virtual)
    status_code = alias&.counter - 1
}
