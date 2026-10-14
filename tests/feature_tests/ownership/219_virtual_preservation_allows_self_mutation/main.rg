Mutator#(.Participant: Type): Contract = (
    .mutate: (.self: $&Participant) -> () where {}
)

Keeping: Type = (.counter: Int32)

Mutating: Type = (.counter: Int32)

implement Mutator#(Keeping) (.mutate = _impl_mutate_Keeping)
implement Mutator#(Mutating) (.mutate = _impl_mutate_Mutating)

_impl_mutate_Keeping := (.self: $&Keeping) -> ()  {}

_impl_mutate_Mutating := (.self: $&Mutating) -> ()  {
    self&.counter = self&.counter + 1
}

register_keeping(.value: $&Keeping) -> () := {
    _ ::= to_virtual#(.abstract: Mutator)(.value = value)
}

main() -> (.status_code: Int32) := {
    keeping :: Keeping = (.counter = 0)
    register_keeping(.value = $&keeping)
    value :: Mutating = (.counter = 0)
    virtual ::= to_virtual#(.abstract: Mutator)(.value = $&value)
    mutate(.self = $&virtual)
    status_code = value.counter - 1
}
