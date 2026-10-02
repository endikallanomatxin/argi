Mutator : Abstract = (
    mutate(.self: $&Self) -> ()
)

Stateful : Type = (.counter: Int32)
Noop : Type = (.marker: UInt8)
Stateful implements Mutator
Noop implements Mutator

mutate(.self: $&Stateful) -> () := {
    self& = (.counter = self&.counter + 1)
}

mutate(.self: $&Noop) -> () := {}

register_noop(.value: $&Noop) -> () := {
    _ ::= to_virtual#(.abstract: Mutator)(.value = value)
}

main() -> (.status_code: Int32) := {
    noop ::= Noop(.marker = 0)
    register_noop(.value = $&noop)
    state ::= Stateful(.counter = 0)
    alias ::= $&state
    virtual ::= to_virtual#(.abstract: Mutator)(.value = $&state)
    mutate(.self = $&virtual)
    status_code = alias&.counter - 1
}
