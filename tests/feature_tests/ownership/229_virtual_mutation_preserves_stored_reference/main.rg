Mutator#(.Participant: Type): Contract = (
    .mutate: (.self: $&Participant) -> () where {}
)

Stateful: Type = (.counter: Int32)

Holder: Type = (.state: $&Stateful)

Noop: Type = (.marker: UInt8)

implement Mutator#(Stateful) (.mutate = _impl_mutate_Stateful)
implement Mutator#(Noop) (.mutate = _impl_mutate_Noop)

_impl_mutate_Stateful := (.self: $&Stateful) -> ()  {
    self&.counter = self&.counter + 1
}

_impl_mutate_Noop := (.self: $&Noop) -> ()  {}

register_noop(.value: $&Noop) -> () := {
    _ ::= to_virtual#(.abstract: Mutator)(.value = value)
}

main() -> (.status_code: Int32) := {
    noop ::= Noop(.marker = 0)
    register_noop(.value = $&noop)
    state ::= Stateful(.counter = 0)
    holder ::= Holder(.state = $&state)
    virtual ::= to_virtual#(.abstract: Mutator)(.value = $&state)
    mutate(.self = $&virtual)
    status_code = holder.state&.counter - 1
}
